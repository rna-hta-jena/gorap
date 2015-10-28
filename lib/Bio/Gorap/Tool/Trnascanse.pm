package Bio::Gorap::Tool::Trnascanse;

use Moose; with 'Bio::Gorap::ToolI';

use IO::Select;
use IO::Pipe;
use POSIX qw(:sys_wait_h);				
use IPC::Open3;
use File::Spec::Functions;
use Symbol qw(gensym);

sub calc_features {
	my ($self) = @_;
	
	#calculations and software calls
	#results are fetched and stored in DB structure
	for (0..$#{$self->parameter->genomes}){				
		my $abbr = ${$self->parameter->abbreviations}[$_];
		#skip redundand calculations
		my @f = $self->gffdb->db->{$abbr}->features(-attributes => {source => 'GORAP'.$self->tool});
		return if $#f > -1;
	
		for my $rfrna ( qw(RF00005_tRNA RF01852_tRNA-Sec) ){
			for my $f ($self->gffdb->db->{$abbr}->features(-primary_tag => $rfrna , -attributes => {source => $self->tool})){
				$self->gffdb->db->{$abbr}->delete($f);
				if (exists $self->stkdb->db->{$rfrna}){								
					$self->stkdb->db->{$rfrna}->remove_seq($_) for $self->stkdb->db->{$rfrna}->get_seq_by_id($f->seq_id);								
				}
			}				
		}
	}

	my $kingdom;	
	$kingdom = 'A' if exists $self->parameter->kingdoms->{'arc'};
	$kingdom = 'B' if exists $self->parameter->kingdoms->{'bac'};
	undef $kingdom if exists $self->parameter->kingdoms->{'euk'} || exists $self->parameter->kingdoms->{'fungi'};	
	
	my $select = IO::Select->new();
	my $thrs={};
	my @out;
	for my $genome (@{$self->fastadb->chunks}){				
		if (scalar(keys %{$thrs}) >= $self->threads){
			my $pid = wait();
			delete $thrs->{$pid};		
			while( my @responses = $select->can_read(0) ){
				for my $pipe (@responses){					
					push @out , $_ while <$pipe>;						
					$select->remove( $pipe->fileno() );
				}
			}
		}
		
		my $pipe = IO::Pipe->new();			
		if (my $pid = fork()) {
			$pipe->reader();
			$select->add( $pipe );
			$thrs->{$pid}++;
		} else {
			$pipe->writer();
			$pipe->autoflush(1);
			for (@{$self->parameter->cfg->cmd}){
				$_ =~ s/\$genome/$genome/;
				if ($kingdom){
					$_ =~ s/\$kingdom/$kingdom/;
				} else {
					$_ =~ s/-\$kingdom//;
				}
			}								
			my $pid = open3(gensym, \*READER, File::Spec->devnull , join ' ' , @{$self->parameter->cfg->cmd});				
			while( <READER> ) {						
				chomp $_;
				$_ =~ s/^\s+|\s+$//g;
				next if $_=~/^#/;
				next if $_=~/^\s*$/;	
				my @l = split /\s+/ , $_;
				next if $#l < 8;					
				print $pipe $_."\n";					;
			}
			waitpid($pid, 0);
			exit;
		}
	}
	for (keys %{$thrs} ) {
		
		my $pid = wait;
		delete $thrs->{$pid};
		while( my @responses = $select->can_read(0) ){
		
			for my $pipe (@responses){					
				push @out , $_ while <$pipe>;										
				$select->remove( $pipe->fileno() );
			}
		}
	}
	my $uid;
	for (@out){		
		
		my @l = split /\s+/, $_;
		next if $#l<8;		

		my @backmap;
		my $plus = 1;	
		
		if ($l[2]<$l[3]){
			@backmap = $self->fastadb->chunk_backmap($l[0], $l[2], $l[3]);	
		} else {
			$plus = 0;
			@backmap = $self->fastadb->chunk_backmap($l[0], $l[3], $l[2]);
		}	


		for (@backmap){			
			if ($plus){
				($l[0],$l[2],$l[3]) = @{$_};
			} else {
				($l[0],$l[3],$l[2]) = @{$_};
			}			

			my ($abbr, @header) = split /\./,$l[0];
			$l[0] = join '.' , @header;
			$uid->{$l[0]}++;
			my @gff3entry = &{$self->tool_parser}($uid->{$l[0]},$abbr,$self->parameter->cfg->rf_rna,\@l);
			#due to overlapping chunks check for already annotated genes
			# my $existingFeatures = $self->gffdb->get_overlapping_features(\@gff3entry,$abbr);
			# next if $#{$existingFeatures} > -1;
							
			my $seq = $self->fastadb->get_gff3seq(\@gff3entry);			
			$self->gffdb->add_gff3_entry(\@gff3entry,$seq,$abbr);
		}
	}

}

1;