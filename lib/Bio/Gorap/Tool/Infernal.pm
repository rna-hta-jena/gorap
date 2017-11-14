package Bio::Gorap::Tool::Infernal;

use Moose; with 'Bio::Gorap::ToolI';

use POSIX qw(:sys_wait_h);
use IPC::Open3;
use File::Spec::Functions;
use Symbol qw(gensym);

sub calc_features {
	my ($self) = @_;

	for (0..$#{$self->parameter->genomes}){
		my $genome = ${$self->parameter->genomes}[$_];
		my $abbr = ${$self->parameter->abbreviations}[$_];
		my $threads = $self->threads;
		my $cmd = $self->cmd;
		$cmd=~s/\$genome/$genome/;
		$cmd=~s/\$cpus/$threads/;

		my $pid = open3(gensym, \*READER, File::Spec->devnull, $cmd);
		my $uid;
		while( <READER> ) {
			chomp $_;
			$_ =~ s/^\s+|\s+$//g;
			next if $_=~/^#/;
			next if $_=~/^\s*$/;
			my @l = split /\s+/ , $_;
			next if $#l < 11;

			my $c = ++$uid->{join('.',($abbr,$l[5],$self->parameter->cfg->rf_rna))};
			my @gff3entry = &{$self->tool_parser}($c,$abbr,$self->parameter->cfg->rf_rna,\@l);

			$self->gffdb->add_gff3_entry(\@gff3entry,$self->fastadb->get_gff3seq(\@gff3entry));
		}
		waitpid($pid, 0);
	}
}

1;