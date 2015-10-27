package Bio::Gorap::Parameter;

use Moose; 
use Getopt::Long;
use Pod::Usage;
use Bio::Gorap::CFG;
use Bio::Gorap::Update;
use File::Spec::Functions;
use Switch;
use File::Basename;
use File::Path qw(make_path);
use Try::Tiny;

has 'pwd' => (
	is => 'ro',
    isa => 'Str',
    required => 1
);

has 'pid' => (
	is => 'ro',
    isa => 'Int',
    required => 1
);

has 'commandline' => (
	is => 'ro',
    isa => 'Bool',
    required => 1
);

has 'cfg' => (
	is => 'rw',
	isa => 'Bio::Gorap::CFG'
);

has 'genomes' => (
	is => 'rw',
    isa => 'ArrayRef',
    default => sub { [catfile($ENV{GORAP},'example','ecoli.fa')] }
);

has 'threads' => (
	is => 'rw',
    isa => 'Int',		
    default => 1
);

has 'abbreviations' => (
	is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] }
);

has 'tmp' => (
	is => 'rw',
    isa => 'Str',
    default => sub { 
    	if ($ENV{TMPDIR}){
    		return $ENV{TMPDIR};
    	} elsif (-e catdir(rootdir,'tmp')){
    		return catdir(rootdir,'tmp');
    	} else {
    		make_path(catdir($ENV{GORAP},'tmp'));
    		return catdir($ENV{GORAP},'tmp');
    	}
    }
);

has 'kingdoms' => (
	is => 'rw',
    isa => 'HashRef',		
    default => sub { {bac => 1 , arc => 1 , euk => 1 , fungi => 1 , virus => 1} }
);

has 'queries' => (
	is => 'rw',
    isa => 'ArrayRef',		
    builder => '_set_queries'
);

has 'verbose' => (
	is => 'rw',
	isa => 'Bool',
	default => 1
);

has 'sort' => (
	is => 'rw',
	isa => 'Bool',
	default => 0
);

has 'output' => (
	is => 'rw',
    isa => 'Str',		
    lazy => 1,      
    default => sub { my $self = shift; 
    	make_path(catdir($self->pwd,'gorap_out','alignments'));
		make_path(catdir($self->pwd,'gorap_out','annotations'));
		make_path(catdir($self->pwd,'gorap_out','meta'));
		make_path(catdir($self->pwd,'gorap_out','html'));
    	return catdir($self->pwd,'gorap_out') 
    },
    trigger => \&_make_paths
);

has 'rank' => (
	is => 'rw',
    isa => 'Str',
    predicate => 'has_rank'
);

has 'species' => (
	is => 'rw',
    isa => 'Str',
    predicate => 'has_species'		    
);

has 'bams' => (
	is => 'rw',
    isa => 'ArrayRef',
    predicate => 'has_bams',
);

has 'outgroups' => (
	is => 'rw',
	isa => 'ArrayRef',
	predicate => 'has_outgroups'
);

has 'ogabbreviations' => (
	is => 'rw',
	isa => 'ArrayRef',	
	predicate => 'has_ogabbreviations'
);

sub BUILD {
	my ($self) = @_;
	my $file='x';

	(Getopt::Long::Parser->new)->getoptions (
		'i|fastas=s' => \my $genomes, 
		'o|output=s' => \my $output, 
		'c|cpu=i' => \my $threads,
		'k|kingdom=s' => \my $kingdoms, 
		'q|queries=s' => \my $queries,
		'a|abbreviations=s' => \my $abbreviations,
		'r|rank=s' => \my $rank,
		's|species=s' => \my $species,		
		'og|outgroups=s' => \my $outgroups,
		'oga|outgroupabbreviations=s' => \my $ogabbreviations,
		'b|bam=s' => \my $bams,	
		'update|update=s' => \my $update,
 		'file|file:s' => \$file,
		'h|help' => \my $help,
		'force|force' => \my $force,
		't|tmp:s' => \my $tmp,
		'sort|sort' => \my $sort
	) or pod2usage(-exitval => 0, -verbose => 2) if $self->commandline;

	if ($file && $file ne 'x'){		
		&read_parameter($self,$file);
	} else {
		unless ($force || ! $self->commandline){
			if($update){
				#downloading and parsing latest databases
				switch (lc $update) {
					case 'ncbi' {
						print "Updating NCBI Taxonomy\n";
						Bio::Gorap::Update->dl_ncbi();
						exit;
					}
					case 'silva' {
						print "Updating Silva tree\n";
						Bio::Gorap::Update->dl_silva($self);
						exit;
					}
					case 'rfam' {
						print "Updating Rfam database\n";
						Bio::Gorap::Update->dl_rfam($self);
						exit;
					}
					case 'cfg' {
						print "Updating configuration files\n";
						Bio::Gorap::Update->create_cfgs($self);
						exit;
					}
					else {
						print "Updating all databases\n";																	
						Bio::Gorap::Update->dl_ncbi();
						my $taxdb = Bio::Gorap::DB::Taxonomy->new(
							parameter => $self
						);
						Bio::Gorap::Update->dl_silva($self,$taxdb);
						Bio::Gorap::Update->dl_rfam($self,$taxdb);	
						Bio::Gorap::Update->create_cfgs($self,$taxdb);											
						exit;
					}
				}
			}			
			pod2usage(-exitval => 0, -verbose => 2) if $file eq 'x' && ($help || ! $genomes);
		}

		#store arguments into data structure
		$self->threads($threads) if $threads;
		
		if ($abbreviations){
			&set_genomes($self, [glob $_ for split(/\s*,\s*/,$genomes) }] ,[split(/\s*,\s*/,$abbreviations)])
			push @{$self->abbreviations} , $_ for split(/\s*,\s*/,$abbreviations);
		} else {
			&set_genomes($self, [glob $_ for split(/\s*,\s*/,$genomes) }] );
		}	
		my @ogg;
		my @ogabbre;
		do { push @ogg , glob $_ for split(/\s*,\s*/,$outgroups); $self->outgroups(\@ogg) } if $outgroups;	
		if ($ogabbreviations){
			push @ogabbre , $_ for split(/\s*,\s*/,$ogabbreviations);
			$self->ogabbreviations(\@ogabbre);
		} else {
			for(@ogg){
				my $abbr = basename($_);
				my @abbr = split /\./ , $abbr;
				pop @abbr if $#abbr > 0;
				$abbr = join '' , @abbr;				
				$abbr=~s/\W//g;				
				push @ogabbre; , $abbr;
			}
			$self->ogabbreviations(\@ogabbre);
		}		
		if($kingdoms){
			$self->kingdoms({});
			for (split(/\s*,\s*/,$kingdoms)) {
				my $s = lc $_;
				pod2usage(-exitval => 0, -verbose => 2) unless $s =~ /^(bac|arc|euk|fungi|virus)$/;
				$self->kingdoms->{$s}=1
			}
		}		
		
		&set_queries($self,$queries) if defined $queries;		
		
		if ($bams){
			my @bams;
			push @bams , glob $_ for split(/\s*,\s*/,$bams);
			$self->bams(\@bams);
		}		
		if ($output){
		    try {
				make_path(catdir(rootdir, $output)); 
				$self->output($output);
		    } catch {
				$self->output(catdir($self->pwd, $output));
		    };
			
		}
		$self->rank($rank) if $rank;
		$self->species($species) if $species;				
		$self->tmp($tmp) if $tmp;
		$self->sort(1) if $sort;
	}	
}

sub _make_paths {
	my ($self) = @_;
	
	make_path(catdir($self->output,'alignments'));
	make_path(catdir($self->output,'annotations'));
	make_path(catdir($self->output,'meta'));
	make_path(catdir($self->output,'html'));
}

sub set_genomes {
	my ($self, $genomes, $abbreviations) = @_;

	undef @{$self->genomes};
	$self->genomes($genomes);

	if ($abbreviations){
		undef @{$self->abbreviations};
		$self->abbreviations($abbreviations);
	} else {
		for(@{$self->genomes}){
			my $abbr = basename($_);
			my @abbr = split /\./ , $abbr;
			pop @abbr if $#abbr > 0;
			$abbr = join '' , @abbr;				
			$abbr=~s/\W//g;				
			push @{$self->abbreviations} , $abbr;
		}
	}
}

#store parsed rfam query related gorap configuration file of interest
sub set_cfg {
	my ($self,$cfg) = @_;	
	
	$self->cfg(Bio::Gorap::CFG->new(
		cfg => $cfg
	));
}

sub set_queries {
	my ($self,$queries) = @_;

	$self->queries(&_set_queries()) , return unless $queries;

	#get the rfam queries related gorap configuration files
	my @queries;
	for (@$queries){
		if ($_=~/R?F?0*(\d+)\s*:\s*R?F?0*(\d+)/){
			push @queries , glob(catfile($ENV{GORAP},'parameter','config','RF'.((0) x (5-length($_))).$_.'*.cfg')) for ($1..$2);
		}elsif($_=~/R?F?0*(\d+)\s*:\s*/) {
			my $nr1 = $1;
			my @q = glob(catfile($ENV{GORAP},'parameter','config','*.cfg'));
			basename($q[$#q])=~/R?F?0*(\d+)/;
			my $nr2=$1;										
			push @queries , glob(catfile($ENV{GORAP},'parameter','config','RF'.((0) x (5-length($_))).$_.'*.cfg')) for ($nr1..$nr2);				
		} elsif ($_=~/R?F?0*(\d+)/){
			push @queries , glob(catfile($ENV{GORAP},'parameter','config','RF'.((0) x (5-length($1))).$1.'*.cfg'))
		} else {
			my @q = glob(catfile($ENV{GORAP},'parameter','config','*.cfg'));
			basename($q[-1])=~/R?F?0*(\d+)/;
			my $nr2=$1;
			my $nr1=1;
			if ($#queries > -1){
				$queries[-1]=~/R?F?0*(\d+)/;
				pop @queries;
				$nr1=$1;
			}														
			push @queries , glob(catfile($ENV{GORAP},'parameter','config','RF'.((0) x (5-length($_))).$_.'*.cfg')) for ($nr1..$nr2);
		}
	}

	$self->queries(\@queries);
}

sub _set_queries {
	my ($self) = @_;

	my @queries;
	push @queries , glob(catfile($ENV{GORAP},'parameter','config','*.cfg'));

	return \@queries;
}

sub read_parameter {
	my ($self,$file) = @_;

	my $c=-1;
	my @genomes;
	my @abbreviations;
	my @ogenomes;
	my @ogabbreviations;
	my @queries;
	my $kingdoms;
	open PARAM , '<'.$file or die $!;
	while(<PARAM>){
		chomp $_ ;
		$_ =~ s/^\s+|\s+$//g;
		if ($_=~/^#/){
			$c++;
			next;
		}
		switch ($c) {
			case 0 {
				if ($_){															
					my @abbrPath =  split /\s+/ , $_;
					if( $#abbrPath > 0 ){						
						push @genomes , $abbrPath[1]; 
						push @abbreviations , $abbrPath[0];
					} else {
						push @genomes , glob $_;	
						for (glob $_){
							my $abbr = basename($_);
							my @abbr = split /\./ , $abbr;
							pop @abbr if $#abbr > 0;
							$abbr = join '' , @abbr;
							$abbr=~s/\W//g;
							push @abbreviations , $abbr;
						}						
					}						
				}	
			}				
			case 1 {
				$self->output($_) if $_;				
			}
			case 2 {				
				$self->threads($_) if $_;				
			}
			case 3 {
				if ($_) {				
					if($_=~/,/){											
						for (split(/\s*,\s*/,$_)) {
							my $s = lc $_;
							$kingdoms->{$s}=1;
						}
					} else {				
						$kingdoms->{$_}=1
					}
				}				
			}
			case 4 { 
				if ($_){															
					if ($_=~/R?F?0*(\d+):R?F?0*(\d+)/){
						push @queries , glob(catfile($ENV{GORAP},'parameter','config','RF'.((0) x (5-length($_))).$_.'*.cfg')) for ($1..$2);
					} elsif($_=~/R?F?0*(\d+):/) {
						my $nr=$1;	

						my ($file) = glob(catfile($ENV{GORAP},'parameter','config','RF'.((0) x (5-length($nr))).$nr.'*.cfg'));						
						while( $file && -e $file ){
							push @queries , $file;
							$nr++;							
							($file) = glob(catfile($ENV{GORAP},'parameter','config','RF'.((0) x (5-length($nr))).$nr.'*.cfg'));							
						}												
					} else {
						$_=~/R?F?0*(\d+)/;		
						push @queries , glob(catfile($ENV{GORAP},'parameter','config','RF'.((0) x (5-length($1))).$1.'*.cfg'));
					}
				}
			}
			case 5 {
				$self->rank($_) if $_;
			}
			case 6 {
				$self->species($_) if $_;
			}
			case 7 {
				if ($_){															
					my @abbrPath =  split /\s+/ , $_;
					if( $#abbrPath > 0 ){						
						push @ogenomes , $abbrPath[1]; 
						push @ogabbreviations , $abbrPath[0];
					} else {
						push @ogenomes , glob $_;	
						for (glob $_){
							my $abbr = basename($_);
							my @abbr = split /\./ , $abbr;
							pop @abbr if $#abbr > 0;
							$abbr = join '' , @abbr;
							$abbr=~s/\W//g;
							push @ogabbreviations , $abbr;
						}						
					}						
				} 
			}															
			case 8 {
				push @{$self->bams} , glob $_ if $_; 
			}			
			else {}
		}
	}
	close PARAM;
	$self->genomes(\@genomes) if $#genomes > -1;
	$self->abbreviations(\@abbreviations) if $#abbreviations > -1;
	$self->outgroups(\@ogenomes) if $#ogenomes > -1;
	$self->ogabbreviations(\@ogabbreviations) if $#ogabbreviations > -1;
	$self->queries(\@queries) if $#queries > -1;
	$self->kingdoms($kingdoms);

}

1;
