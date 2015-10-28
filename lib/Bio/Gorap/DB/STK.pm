package Bio::Gorap::DB::STK;

use Moose;
use Bio::AlignIO;
use File::Basename;
use File::Spec::Functions;
use Bio::Gorap::Functions::STK;
use IPC::Cmd qw(run);
use POSIX;

#uses the gorap parameter object to initialize the 
#database of Bio::Align::Stockholm  objects
has 'parameter' => (
	is => 'ro',
	isa => 'Bio::Gorap::Parameter',
	required => 1 ,
	trigger => \&_set_db 
);

#genome file based hashmap of Bio::Align::AlignI databases
has 'db' => (
	is => 'rw',
	isa => 'HashRef',
	default => sub { {} }
);

#gorap specific mapping
has 'idToPath' => (
	is => 'rw',
	isa => 'HashRef',
	default => sub { {} }
);

#set up database taking existing alignments into account
sub _set_db {
	my ($self) = @_;	

	for (@{$self->parameter->queries}){
		my $rf_rna = basename($_);
		$rf_rna=~s/\.cfg//;				
		my $file = catfile($self->parameter->output,'alignments',$rf_rna.'.stk');				

		#use gorap specific access ids: the rfam id and rna name		
		&add_stk($self,$rf_rna,$file) if -e $file;							
	}
}

#for manually adding files into this hashed database: 
sub add_stk {
	my ($self,$id,$file) = @_;

	$self->idToPath->{$id} = $file;
	my $io = Bio::AlignIO->new(-format => 'stockholm', -file => $file, -verbose => -1);

	$self->db->{$id} = $io->next_aln;
	$self->db->{$id}->set_displayname_flat;
}

sub store {
	my ($self,$id) = @_;
	
	if ($id){
		(Bio::AlignIO->new(-format => 'stockholm', -file => '>'.$self->idToPath->{$id}, -verbose => -1))->write_aln($self->db->{$id});
	} else {
		for (keys %{$self->db}){
			&remove_gap_columns_and_write($self,$self->db->{$_},$self->idToPath->{$_});			
		}	
	}
}

sub store_stk {
	my ($self,$stk, $file, $taxdb) = @_;

	$stk = $taxdb->sort_stk($stk) if $taxdb;
	(Bio::AlignIO->new(-format => 'stockholm', -file => '>'.$file, -verbose => -1))->write_aln($stk);
}

sub remove_gap_columns_and_write {
	my ($self , $stk, $file) = @_;		
	my $tmpstk = $stk;	
	
	my ($ss , $sc) = Bio::Gorap::Functions::STK->get_ss_cs_from_object($stk);
	my @ss = split // , $ss;
	my @sc = split // , $sc;
	
	my $del = 0 ;
	$tmpstk->map_chars('\.','-');
	my @gapcolm = @{$stk->gap_col_matrix};
	for (my $i=$#gapcolm; $i>=0; $i-- ){	
		my $absent = 0;
		for my $k (keys %{$gapcolm[$i]}){				
			$absent += $gapcolm[$i]->{$k};
		}		
		
		if($absent == $tmpstk->num_sequences){
			$del = 1;
			$tmpstk = $tmpstk->remove_columns([$i,$i]);
			splice(@sc, $i, 1);
			splice(@ss, $i, 1);		
		}	
	}
	
	$tmpstk->set_displayname_flat;
	
	if ($del){
		my $out;		
		open my $READER, '>', \$out;		
		(Bio::AlignIO->new(-format  => 'stockholm', -fh => $READER, -verbose => -1 ))->write_aln($tmpstk);
		close $READER;
		my @lines = split /\n/ , $out;
		$lines[-1] = '#=GC RF '.join('',(' ') x ($tmpstk->maxdisplayname_length()-7)).' '.join('' , @sc);
		push @lines , '#=GC SS_cons '.join('',(' ') x ($tmpstk->maxdisplayname_length()-12)).' '.join('' , @ss);
		push @lines, '//';
		
		open STK , '>'.$file or die $!;
		print STK $_."\n" for @lines;
		close STK;

		my $retaln = (Bio::AlignIO->new(-file => $file, -format => 'stockholm'))->next_aln;
		$retaln->set_displayname_flat;
		return $retaln;
	} else {
		(Bio::AlignIO->new(-format => 'stockholm', -file => '>'.$file, -verbose => -1))->write_aln($stk);
		return $stk;
	}
		
}

#align annotated sequences given as referenced array of Bio::Seq objects against the
#covariance model of gorap or a given one. resulting alignments are merged with those
#read into this hashreferenced database of Bio::Align::Stockholm objects
sub align {
	my ($self,$id,$sequences,$threads,$cm) = @_;

	my $scorefile = catfile($self->parameter->tmp,$self->parameter->pid.'.score');
	my $tmpfile = catfile($self->parameter->tmp,$self->parameter->pid.'.stk');
	my $stkfile = catfile($self->parameter->output,'meta',$id.'.stk');
	my $fastafile = catfile($self->parameter->output,'meta',$id.'.fa');	

	#print new annotated sequences into fasta file for aligning it via cmalign
	open FA , '>'.$fastafile or die $!;	
	print FA '>'.$_->display_id."\n".$_->seq."\n" for @{$sequences};	
	close FA;

	my ($cmd, $success, $error_code, $full_buf, $stdout_buf, $stderr_buf);	
	#if database was initialized with existing alignment, the new sequences are aligned in single, to merge 2 alignment files afterwards
	if (exists $self->db->{$id}){
		#save before merging files, to apply deletions of existing sequences in this object, performed in BUILD of Bio::Gorap::ToolI
		&store($self,$id);

		#align against gorap cfg default or given cm
		if ($cm){
			$cmd = "cmalign --mxsize 7000 --noprob --sfile $scorefile --cpu $threads -o $tmpfile $cm $fastafile";			
		} else {			
			$cmd = "cmalign --mxsize 7000 --noprob --sfile $scorefile --cpu $threads -o $tmpfile ".$self->parameter->cfg->cm." $fastafile";			
		}
		($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = run( command => $cmd , verbose => 0 );

		#try to merge both alignments, which is oly possible, if both were created by the same cm
		#if it fails, all sequences are extracted as fasta to align them in total
		$cmd = "esl-alimerge --rna -o $stkfile ".$self->idToPath->{$id}." $tmpfile";		

		($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = run( command => $cmd , verbose => 0 );
		unless ($success){
			open FA , '>'.$fastafile or die $!;			
			for ($self->db->{$id}->each_seq){				
				my $s = $_->seq; 
				$s=~s/\W//g;
				$s=uc($s);
				print FA '>'.$_->id."\n".$s."\n";
			}			
			print FA '>'.$_->display_id."\n".$_->seq."\n" for @{$sequences};
			close FA;
			$cmd = $cm ? "cmalign --mxsize 7000 --noprob --sfile $scorefile --cpu $threads -o $stkfile $cm $fastafile" : "cmalign --mxsize 7000 --noprob --sfile $scorefile --cpu $threads -o $stkfile ".$self->parameter->cfg->cm." $fastafile";		
			($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = run( command => $cmd , verbose => 0 );			
		}
	} else { 
		#if no alignment is present, the seed alignment the cm is build from, is added to the alignment process
		$cmd = $cm ? "cmalign --mxsize 7000 --noprob --sfile $scorefile --cpu $threads -o $stkfile $cm $fastafile" : "cmalign --mxsize 7000 --noprob --sfile $scorefile --cpu $threads --mapali ".$self->parameter->cfg->stk." -o $stkfile ".$self->parameter->cfg->cm." $fastafile";

		($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = run( command => $cmd , verbose => 0 );		
		unless ($success) {
			$tmpfile = catfile($self->parameter->tmp,$self->parameter->pid.'.fa');
			open FA , '>'.$tmpfile or die $!;			
			open FAI , '<'.$self->parameter->cfg->fasta or die $!;
			while(<FAI>){
				if($_=~/^>(.+?)\s+(.+?)\s*$/){
					print FA '>'.($2 ? $2 : $1)."\n";					
				} else {
					print FA $_;
				}				
			}
			print FA '>'.$_->display_id."\n".$_->seq."\n" for @{$sequences};
			close FAI;
			close FA;
			$cmd = $cm ? "cmalign --mxsize 7000 --noprob --sfile $scorefile --cpu $threads -o $stkfile $cm $tmpfile" : "cmalign --mxsize 7000 --noprob --sfile $scorefile --cpu $threads -o $stkfile ".$self->parameter->cfg->cm." $tmpfile";
			($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = run( command => $cmd , verbose => 0 );
		}
	}
	
	unlink $tmpfile;

	&add_stk($self,$id,$stkfile);

	return ($scorefile , $self->db->{$id});
}

sub calculate_threshold {
	my ($self,$cpus,$relatedRankIDsToLineage,$relatedSpeciesIDsToLineage) = @_;
	$relatedRankIDsToLineage = {} unless $relatedRankIDsToLineage;
	$relatedSpeciesIDsToLineage = {} unless $relatedSpeciesIDsToLineage;	

	my $threshold=999999;	
	if ($self->parameter->cfg->bitscore == $self->parameter->cfg->bitscore_cm){
		#check taxonomy to create own bitscore, else use Rfam bitscore threshold
		if (scalar keys %$relatedSpeciesIDsToLineage > 0 || scalar keys %$relatedRankIDsToLineage > 0){
			my @sequences;
			my $fasta = Bio::SeqIO->new(-file => $self->parameter->cfg->fasta , -format => 'Fasta', -verbose => -1);

			my ($inRank,$inSpecies);	
			while ( my $s = $fasta->next_seq() ) {				
				if ($s->id=~/^(\d+)/){
					push @{$inSpecies} , $s if exists $relatedSpeciesIDsToLineage->{$1};
					push @{$inRank} , $s if exists $relatedRankIDsToLineage->{$1};
				}
			}

			my ($scorefile,$taxstk);
			if ($#{$inSpecies} > -1 ){
				($scorefile,$taxstk) = &align(
					$self,
					$self->parameter->cfg->rf_rna.'.tax',
					$inSpecies,
					$cpus,
					$self->parameter->cfg->cm
				);
			}elsif($#{$inRank} > -1){
				($scorefile,$taxstk) = &align(
					$self,
					$self->parameter->cfg->rf_rna.'.tax',
					$inRank,
					$cpus,
					$self->parameter->cfg->cm
				);
			}
			
			if ($scorefile){
				open S , '<'.$scorefile or die $!;
				while(<S>){								
					chomp $_ ;
					$_ =~ s/^\s+|\s+$//g;
					next if $_=~/^#/;
					my @l = split /\s+/ , $_;					
					$threshold = $l[6] if $l[6] < $threshold;
				}
				close S;

				if ($threshold * 0.8 < $self->parameter->cfg->bitscore){
					$threshold = floor($threshold);
				} elsif ($threshold * 0.7 < $self->parameter->cfg->bitscore){
					$threshold = floor($threshold * 0.8);
				} else {
					$threshold = floor($threshold * 0.7);
				}	
				#returns threshold and nonTaxThreshold
				return ($threshold,floor($self->parameter->cfg->bitscore * 0.8));			
			} else {
				$threshold = floor($self->parameter->cfg->bitscore * 0.8) ;
				return ($threshold,0);
			}
		} else {
			$threshold = floor($self->parameter->cfg->bitscore * 0.8);
		}
	} else {
		#use user bitscore
		$threshold = $self->parameter->cfg->bitscore;
	}

	return ($threshold,0);
}

#gorap post stk filters
#gets stk as Bio::SimpleAlign, HashRef of Bio::SeqFeatures and threshold as float
sub filter_stk {
	my ($self, $id, $stk, $features, $threshold, $nonTaxThreshold, $taxdb) = @_;	
	
	$stk = $taxdb->sort_stk($stk) if $taxdb && $self->parameter->sort;
	
	my $c=0; 
	#necessary for deleten to map $c->feature , because 2 features can have same identifier if called print $object 
	#due to seqfeature doesnt return memory references
	$features = {map { $c++ => $_ } @{$features}} if ref($features) eq 'ARRAY';
	
	my @update;
	my $up;
	my $write;
		
	($stk, $features, $up, $write) = Bio::Gorap::Functions::STK->score_filter($stk, $features, $threshold, $nonTaxThreshold);
	push @update , @{$up} if $up;
	$stk = &remove_gap_columns_and_write($self,$stk,catfile($self->parameter->output,'meta',$id.'.B.stk'));# if $write;

	return @update if scalar keys %{$features} == 0;

	($stk, $features, $up, $write) = Bio::Gorap::Functions::STK->structure_filter($stk, $features);	
	push @update , @{$up} if $up;
	$stk = &remove_gap_columns_and_write($self,$stk,catfile($self->parameter->output,'meta',$id.'.S.stk'));# if $write;

	return @update if scalar keys %{$features} == 0;

	if ($self->parameter->cfg->userfilter){		
		($stk, $features, $up, $write) = Bio::Gorap::Functions::STK->user_filter($stk, $features, $self->parameter->cfg->cssep, $self->parameter->cfg->csindels);	
		push @update , @{$up} if $up;
		$stk = &remove_gap_columns_and_write($self,$stk,catfile($self->parameter->output,'meta',$id.'.U.stk'));# if $write;
	} else {
		($stk, $features, $up, $write) = Bio::Gorap::Functions::STK->sequence_filter($stk, $features);	
		push @update , @{$up} if $up;
		$stk = &remove_gap_columns_and_write($self,$stk,catfile($self->parameter->output,'meta',$id.'.P.stk'));# if $write;
	}
	return @update if scalar keys %{$features} == 0;

	if (scalar keys %{$features} > $self->parameter->cfg->pseudogenes){
		my @featureKeys = reverse sort { $features->{$a}->score <=> $features->{$b}->score } keys %{$features};
		for ($self->parameter->cfg->pseudogenes + 1 .. scalar keys %{$features}){
			my $f = $features->{$featureKeys[$_]};
			delete $features->{$featureKeys[$_]};
			$stk->remove_seq($stk->get_seq_by_id($f->seq_id)); 
			push @update , $f->seq_id.' '.$f->primary_tag.' H';
		}
		$stk = &remove_gap_columns_and_write($self,$stk,catfile($self->parameter->output,'meta',$id.'.H.stk'));# if $write;	
	}		

	$stk = &remove_gap_columns_and_write($self,$stk,catfile($self->parameter->output,'alignments',$id.'.stk'),$taxdb) if scalar keys %{$features} > 0;			

	return @update;	
}

sub scorefilter_stk {
	my ($self, $id, $stk, $features, $threshold, $nonTaxThreshold, $taxdb) = @_;	
	
	my $c=0; 
	#necessary for deleten to map $c->feature , because 2 features can have same identifier if called print $object 
	#due to seqfeature doesnt return memory references
	$features = {map { $c++ => $_ } @{$features}} if ref($features) eq 'ARRAY';
	
	my @update;
	my $up;
	my $write;
		
	($stk, $features, $up, $write) = Bio::Gorap::Functions::STK->score_filter($stk, $features, $threshold, $nonTaxThreshold);
	push @update , @{$up} if $up;
	$stk = &remove_gap_columns_and_write($self,$stk,catfile($self->parameter->output,'meta',$id.'.B.stk')); #if $write;	

	if (scalar keys %{$features} > $self->parameter->cfg->pseudogenes){
		my @featureKeys = reverse sort { $features->{$a}->score <=> $features->{$b}->score } keys %{$features};
		for ($self->parameter->cfg->pseudogenes + 1 .. scalar keys %{$features}){
			my $f = $features->{$featureKeys[$_]};
			delete $features->{$featureKeys[$_]};
			$stk->remove_seq($stk->get_seq_by_id($f->seq_id)); 
			push @update , $f->seq_id.' '.$f->primary_tag.' H';
		}
		$stk = &remove_gap_columns_and_write($self,$stk,catfile($self->parameter->output,'meta',$id.'.H.stk'));# if $write;	
	}	

	$stk = &remove_gap_columns_and_write($self,$stk,catfile($self->parameter->output,'alignments',$id.'.stk'),$taxdb) if scalar keys %{$features} > 0;

	return @update;	
}

1;