package Bio::Gorap::Tool::Blast;

use Moose; with 'Bio::Gorap::ToolI';
use POSIX qw(:sys_wait_h);				
use File::Spec::Functions;
use IPC::Cmd qw(run);
use IPC::Open3;
use List::Util qw(max);
use Symbol qw(gensym);

sub calc_features {
	my ($self) = @_;
	
	#calculations and software calls
	#results are fetched and stored in DB structure

	for (0..$#{$self->parameter->genomes}){		
		my $genome = ${$self->parameter->genomes}[$_];
		my $abbr = ${$self->parameter->abbreviations}[$_];		
		my $uid = 0;				

		unless (-e $genome.'.nhr'){
			unlink $genome.$_ for qw( .nhr .nin .nnd .nni .nog .nsd .nsi .nsq);			
			my ($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = run( command => "makeblastdb -in $genome -dbtype nucl -parse_seqids -gi_mask" , verbose => 0 );
		}
		my @cmd = ('blastn' , '-num_threads' , $self->threads , '-query' , $self->parameter->cfg->fasta , '-db' , $genome , '-task' , 'dc-megablast' , 
			'-word_size' , 11 , '-template_type' , 'optimal' , '-template_length' , 16 , '-evalue' , $self->parameter->cfg->evalue , '-window_size' , 50 , 
			'-outfmt' , '"6' , 'qseqid' , 'sseqid' , 'pident' , 'length' , 'mismatch' , 'gapopen' , 'qstart' , 'qend' , 'sstart' , 'send' , 'evalue' , 'bitscore"'
		);
		# my @cmd = ('blastn' , '-num_threads' , $self->threads , '-query' , $self->parameter->cfg->fasta , '-db' , $genome , '-task' , 'dc-megablast' , 
		# 	'-evalue' , $self->parameter->cfg->evalue , '-window_size' , 50 , 
		# 	'-outfmt' , '"6' , 'qseqid' , 'sseqid' , 'pident' , 'length' , 'mismatch' , 'gapopen' , 'qstart' , 'qend' , 'sstart' , 'send' , 'evalue' , 'bitscore"'
		# );
				
		my $pid = open3(gensym, \*READER, File::Spec->devnull , join(' ' , @cmd));				
		my @tab;
		while( <READER> ) {		
			chomp $_;
			$_ =~ s/^\s+|\s+$//g;
			next if $_=~/^#/;
			next if $_=~/^\s*$/;
			my @l = split /\s+/ , $_;
			
			if ($l[8]>$l[9]){
				push @tab, $l[1]."\tBlast\t".$self->parameter->cfg->rf_rna."\t$l[9]\t$l[8]\t$l[11]\t-\t$l[10]\t$l[0]\t$l[6]\t$l[7]";			
			} else {				
				push @tab, $l[1]."\tBlast\t".$self->parameter->cfg->rf_rna."\t$l[8]\t$l[9]\t$l[11]\t+\t$l[10]\t$l[0]\t$l[6]\t$l[7]";			
			}
		}
		waitpid($pid, 0);

		for (@{&merge_gff($self,\@tab)}){
			#tool_parser is set to blast_parser via Gorap.pl, static defined in Bio::Gorap::Functions::ToolParser			
			chomp $_;
			my @l = split /\s+/ , $_;
			
			my $add = 1;			
			for ($self->gffdb->db->{$abbr}->features(-primary_tag => $self->parameter->cfg->rf_rna , -attributes => {source => 'GORAPinfernal'})){				
				next unless $l[6] eq ($_->strand == 1 ? '+' : '-');
				next unless $_->seq_id=~/$l[0]/;
				#dont add into gff database if overlap with already done annotation by infernal				
				$add = 0 if $l[3] < $_->stop && $l[4] > $_->start;								
			}		
			if ($add){
				my @gff3entry = &{$self->tool_parser}(++$uid,$abbr,$self->parameter->cfg->rf_rna,\@l);										
				my $seq = $self->fastadb->get_gff3seq(\@gff3entry);	
				$self->gffdb->add_gff3_entry(\@gff3entry,$seq,$abbr) if $add;
			}
		}
	}	
}

sub merge_gff {
	my ($self,$s) = @_;

	my @tab = @{$s};
	@tab = sort{ ((split /\s+/, $a)[6] || "") cmp ((split /\s+/, $b)[6] || "") || ((split(/\s+/,$a))[0]) cmp ((split(/\s+/,$b))[0]) || ((split(/\s+/,$a))[3]) <=> ((split(/\s+/,$b))[3]) || ((split(/\s+/,$a))[4]) <=> ((split(/\s+/,$b))[4]) } @tab;

	my ($id, $strand, $sta, $sto, $q, $e);

	my @tmp;
	my @merge;
	for my $item (@tab){
		@tmp=split(/\s+/,$item);
		if (defined $id && $tmp[0] eq $id && $tmp[6] eq $strand && $tmp[3]-1<=$sto){			
			$sto=max($sto,$tmp[4]);								
			if ($tmp[5]>$e){
				$e=$tmp[5];
				$q=join("\t",@tmp[7..$#tmp]);																								
			} 						
		} else {										
			push @merge, $id."\t".$tmp[1]."\t".$tmp[2]."\t".$sta."\t".$sto."\t".$e."\t".$strand."\t".$q if defined $id;							 
			$id=$tmp[0];
			$strand=$tmp[6];
			$sta=$tmp[3];
			$sto=$tmp[4];
			$e=$tmp[5];
			$q=join("\t",@tmp[7..$#tmp]);									
		}				
	}	
	push @merge, $id."\t".$tmp[1]."\t".$tmp[2]."\t".$sta."\t".$sto."\t".$e."\t".$strand."\t".$q if defined $id;

	return \@merge;
}