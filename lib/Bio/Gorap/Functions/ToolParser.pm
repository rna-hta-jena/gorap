package Bio::Gorap::Functions::ToolParser;

use List::Util qw(min max);

#gorap specific gff3 parser for Bio::DB::SeqFeature objects
sub gff3_parser {	
	my ($uid,$abbr,$rfrna,$s) = @_;	
	
	my @l = @{$s};
	$l[0] = $abbr.'.'.$l[0].'.'.$uid;
	$l[1] =~ s/\W//g;
	$l[1] = lc $l[1];
	$l[3] = min(${$s}[3],${$s}[4]);
	$l[4] = max(${$s}[3],${$s}[4]);
	$l[6] = ${$s}[3] < ${$s}[4] ? '+' : '-';
	$#l = 6;
	push @l , '.';
	return @l;
}

#gorap specific cmsearch tabular output parser for Bio::DB::SeqFeature objects
sub infernal_parser {	
	my ($uid,$abbr,$rfrna,$s) = @_;	

	return ($abbr.'.'.${$s}[5].'.i'.$uid , 'GORAPinfernal' , $rfrna , min(${$s}[6],${$s}[7]) , max(${$s}[6],${$s}[7]) , ${$s}[3] , ${$s}[8] , '.');
}

#gorap specific blastn tabular output parser for Bio::DB::SeqFeature objects
sub blast_parser {	
	my ($uid,$abbr,$rfrna,$s) = @_;	
	
	return ($abbr.'.'.${$s}[0].'.b'.$uid , 'GORAPblast' , $rfrna, ${$s}[3], ${$s}[4], ${$s}[5], ${$s}[6], '.');
}

#gorap specific tRNAscan-SE tabular output parser for Bio::DB::SeqFeature objects
sub trnascanse_parser {	
	my ($uid,$abbr,$rfrna,$s) = @_;	
	if (${$s}[4]=~/SeC/){
		$rfrna = 'RF01852_tRNA-Sec';
	} else {
		$rfrna = 'RF00005_tRNA';
	}
	return ($abbr.'.'.${$s}[0].'.'.$uid , 'GORAPtrnascanse' , $rfrna , min(${$s}[2],${$s}[3]) , max(${$s}[2],${$s}[3]) , ${$s}[8] , ${$s}[2] < ${$s}[3] ? '+' : '-' , '.');
}

#gorap specific RNAmmer tabular output parser for Bio::DB::SeqFeature objects
sub rnammer_parser {	
	my ($uid,$abbr,$rfrna,$kingdom,$s) = @_;	

	if ($kingdom eq 'bac'){
		if (${$s}[8] eq '16s_rRNA'){
			$rfrna = 'RF00177_SSU_rRNA_bacteria';
		} elsif (${$s}[8] eq '23s_rRNA'){
			$rfrna = 'RF02541_LSU_rRNA_bacteria';
		} else {
			$rfrna = 'RF00001_5S_rRNA';
		}		
	} elsif ($kingdom eq 'arc') {
		if (${$s}[8] eq '16s_rRNA'){
			$rfrna = 'RF01959_SSU_rRNA_archaea';
		} elsif (${$s}[8] eq '23s_rRNA'){
			$rfrna = 'RF02540_LSU_rRNA_archaea';
		} else {
			$rfrna = 'RF00001_5S_rRNA';
		}
	} elsif ($kingdom eq 'fungi') {
		if (${$s}[8] eq '18s_rRNA'){
			$rfrna = 'RF02542_SSU_rRNA_microsporidia';
			#$rfrna = 'RF01960_SSU_rRNA_eukarya';
		} elsif (${$s}[8] eq '28s_rRNA'){
			$rfrna = 'RF02543_LSU_rRNA_eukarya';
		} else {
			$rfrna = 'RF00001_5S_rRNA';
		}
	} else {
		if (${$s}[8] eq '18s_rRNA'){
			$rfrna = 'RF01960_SSU_rRNA_eukarya';
		} elsif (${$s}[8] eq '28s_rRNA'){
			$rfrna = 'RF02543_LSU_rRNA_eukarya';
		} else {
			$rfrna = 'RF00001_5S_rRNA';
		}
	}
	
	return ($abbr.'.'.${$s}[0].'.'.$uid , 'GORAPrnammer' , $rfrna , ${$s}[3] , ${$s}[4] , ${$s}[5] , ${$s}[6] , '.');
}

#gorap specific Bcheck tabular output parser for Bio::DB::SeqFeature objects
sub bcheck_parser {
	my ($uid,$abbr,$rfrna,$s) = @_;	

	${$s}[0] = substr ${$s}[0] , 1;
	my @l = ( split(/\//,${$s}[0]) , substr((split(/\s+/,${$s}[1]))[2] , 0 , -1) );
	my ($sta,$sto) = split /-/ , $l[1];

	if ($l[3]=~/bac/){
		$rfrna = $line[3] eq 'bacB' ? 'RF00011_RNaseP_bact_b' : 'RF00010_RNaseP_bact_a' ;	
	} elsif($line[3]=~/arc/) {
		$rfrna = 'RF00373_RNaseP_arch';										
	} else {
		$rfrna = 'RF00009_RNaseP_nuc';
	}

	return ($abbr.'.'.$l[0].'.'.$uid , 'GORAPbcheck' , $rfrna , $sta , $sto , $l[4] , $l[2] == -1 ? '-' : '+' , '.');	
}

1;