package Bio::Gorap::Evaluation::HTML;

use Moose;
use File::Spec::Functions;
use File::Basename;

sub create {
	my ($self,$parameter,$gffdb,$headerToDBsize,$idToStk,$filename) = @_;
	my $data_pos = tell DATA;
	my $tablehtml=0;
	open INDEX , '>'.catfile($parameter->output,'index.html') or die $!;
	open HTML , '>'.catfile($parameter->output,'html',$filename.'.html') or die $!;
	while (<DATA>){		
		if ($_ =~ /DOCTYPE/){
			$tablehtml++;			
		}
		if ($tablehtml==1){
			if ($_=~/option value/){
				print INDEX $_;
				for (glob catfile($parameter->output,'html','*.html')){							
					my $file = basename $_;
					next if $file eq $filename.'.html';
					print INDEX '<option value="'.catfile('html',$file).'">'.substr($file,0,-5).'</option>'."\n";
				}	
				print INDEX '<option value="'.catfile('html',$filename.'.html').'">'.$filename.'</option>'."\n";		
			} else {
				print INDEX $_;	
			}
		} else {
			if ($_=~/Parameter/){
				print HTML $_;
				print HTML '-i '.join('\\<br>'."\n",@{$parameter->{'genomes'}}).'\\<br>'."\n";
				print HTML '-a '.join(',',@{$parameter->{'abbreviations'}}).'\\<br>'."\n";
				print HTML '-o '.$parameter->output.'\\<br>'."\n";
				print HTML '-c '.$parameter->threads.'\\<br>'."\n";
				print HTML '-k '.join(',',keys %{$parameter->{'kingdoms'}}).'\\<br>'."\n";
				if ($#{$parameter->queries}>-1){
					basename(${$parameter->queries}[0])=~/RF0*(\d+)/;
					my $q = $1;
					my $qstring=$q;
					for (my $i=1; $i<=$#{$parameter->queries}; $i++){
						basename(${$parameter->queries}[$i])=~/RF0*(\d+)/;
						my $q2 = $1;
						my $range;
						while($q2-$q==1 && $i<$#{$parameter->queries}){
							$range = 1;
							$i++;
							$q = $q2;
							basename(${$parameter->queries}[$i])=~/RF0*(\d+)/;
							$q2 = $1;						
						}
						if ($range){
							$qstring.= $q2-$q==1 ? ':'.$q2 : ':'.$q.','.$q2;
						} else {
							$qstring.=','.$q2;
							$q = $q2;
						}					
					}
					chomp $qstring;
					my @q = $qstring=~/(.{1,100})/g;
					print HTML '-q '.join('\\<br>'."\n",@q).'\\<br>'."\n";
				} else {
					print HTML '-q 0\\<br>'."\n";
				}
				print HTML '-r '.$parameter->{'rank'}.'\\<br>'."\n" if $parameter->has_rank;
				print HTML '-s '.$parameter->{'species'}.'\\<br>'."\n" if $parameter->has_species;
				print HTML '-og '.$parameter->{'outgroup'}.'\\<br>'."\n" if $parameter->has_outgroup;
				print HTML '-oga '.$parameter->{'ogabbreviation'}.'\\<br>'."\n" if $parameter->has_ogabbreviation;
				print HTML '-b '.join(',\\<br>'."\n",@{$parameter->{'bams'}}).'\\<br>'."\n" if $parameter->has_bams;
				print HTML '-t '.$parameter->{'tmp'}.'<br>'."\n";
			} elsif ($_=~/Used data/){
				print HTML $_;
				print HTML '<table class="tablesorter">'."\n";
				print HTML '<thead>'."\n";
				print HTML '<tr>'."\n";
				print HTML '<th>Genome</th>'."\t".'<th>Abbreviation</th>'."\t".'<th>Genomesize</th>'."\t".'<th>File</th>'."\n";
				print HTML '</tr>'."\n";
				print HTML '</thead>'."\n";
				print HTML '<tbody>'."\n";
				for (0..$#{$parameter->genomes}){
					print HTML '<tr>'."\n";
					print HTML '<td>'.${${$headerToDBsize}[$_]}[0].'</td>'."\t";
					print HTML '<td>'.${$parameter->abbreviations}[$_].'</td>'."\t";
					print HTML '<td>'.${${$headerToDBsize}[$_]}[1].'</td>'."\t";
					print HTML '<td><a href="'.${$parameter->genomes}[$_].'">'.basename(${$parameter->genomes}[$_]).'</a></td>'."\n";
					print HTML '</tr>'."\n";	
				}				
				print HTML '</tbody>'."\n";				
				print HTML '</table>'."\n";
			} elsif($_=~/ncRNA annotation/) {
				print HTML $_;
				print HTML '<table class="tablesorter">'."\n";
				print HTML '<thead>'."\n";
				print HTML '<tr>'."\n";
				print HTML '<th>Genome</th>'."\t".'<th>GFF</th>'."\n";
				print HTML '</tr>'."\n";
				print HTML '</thead>'."\n";
				print HTML '<tbody>'."\n";
				for (0..$#{$parameter->genomes}){
					print HTML '<tr>'."\n";					
					print HTML '<td>'.${$parameter->abbreviations}[$_].'</td>'."\t";
					print HTML '<td><a href="../annotations/'.${$parameter->abbreviations}[$_].'.final.gff">final</a> / <a href="../annotations/'.${$parameter->abbreviations}[$_].'.gff">filtered</a></td>'."\n";
					print HTML '</tr>'."\n";	
				}
				print HTML '</tbody>'."\n";				
				print HTML '</table>'."\n";
			} elsif($_=~/ncRNA alignments/){
				print HTML $_;
				print HTML '<table class="tablesorter">'."\n";
				print HTML '<thead>'."\n";
				print HTML '<tr>'."\n";
				print HTML '<th>ncRNA</th>'."\t".'<th>Rfam Accession</th>'."\t".'<th>STK</th>';
				for (@{$parameter->abbreviations}){
					print HTML "\t".'<th>'.$_.'</th>';
				}
				print HTML "\n";				
				print HTML '</tr>'."\n";
				print HTML '</thead>'."\n";
				print HTML '<tbody>'."\n";
				for my $rf_rna (keys %$idToStk){
					my $anno;
					my @counts;
					for (@{$parameter->abbreviations}){						
						push @counts , ($#{$gffdb->get_features($rf_rna,[$_],'!')}+1);
						$anno = 1 if $counts[-1] > 0;
					}
					next unless $anno;
					my ($rf , @rna) = split /_/ , $rf_rna;
					print HTML '<tr>'."\n";
					print HTML '<td>'.join('_',@rna).'</td>'."\t";
					print HTML '<td>'.$rf.'</td>'."\t";
					print HTML '<td><a href="../alignments/'.$rf_rna.'.stk">STK</a></td>';					
					for (@counts){												
						print HTML "\t".'<td>'.$_.'</td>';
					}
					print HTML "\n";
					print HTML '</tr>'."\n";
				}				
				print HTML '</tbody>'."\n";				
				print HTML '</table>'."\n";
			} elsif($_=~/Phylogeny SSU/){
				if ($parameter->has_outgroup){					
					if (-e catfile($parameter->output,'SSU.eps')){
						print HTML $_;	
						print HTML '<a href="../SSU.eps"><img src="../SSU.png" alt="Phylogeny"></a>' ;
					}					
				}
			} elsif($_=~/Phylogeny RNome/){
				if ($parameter->has_outgroup){										
					if (-e catfile($parameter->output,'RNome.eps')){
						print HTML $_;	
						print HTML '<a href="../RNome.eps"><img src="../RNome.png" alt="Phylogeny"></a>' ;
					}
				}
			} else {
				print HTML $_;
			}
		}
	}
	close HTML;
	close INDEX;
	seek DATA, $data_pos, 0;
}

1;

__DATA__

<!DOCTYPE html>
<html>

<head>
    <title>GORAP</title>

    <style> 
    	button {
    		width: 80px
    	}
		#header {
			background-color:black;
			color:white;
			text-align:center;
			padding:1px;
		}
		#nav { 
			float: left;
			line-height:30px;
			background-color:lightgrey;
			width:100px;
			padding:5px;	      
		}
		body {
			text-align:center;
		}
	</style>

	<script>
		function getDocHeight() {
			return Math.max(
				Math.max(document.body.scrollHeight, document.documentElement.scrollHeight),
				Math.max(document.body.offsetHeight, document.documentElement.offsetHeight),
				Math.max(document.body.clientHeight, document.documentElement.clientHeight)
			);
		}
		function getDocWidth() {
			return Math.max(
				Math.max(document.body.scrollWidth, document.documentElement.scrollWidth),
				Math.max(document.body.offsetWidth, document.documentElement.offsetWidth),
				Math.max(document.body.clientWidth, document.documentElement.clientWidth)
			);
		}
		function onResize() {		
			location.reload();
			location.href = location.href;			
		}
		function select() {
			resize();
			var element = document.getElementById("select");
			var value = element.options[element.selectedIndex].value;
			if (value != "select") document.getElementById("frame").src = value;			
		}
		function resize(){
			document.getElementById("frame").height=getDocHeight()-230;
			document.getElementById("frame").width=getDocWidth()-130;
			document.getElementById("nav").setAttribute("style","height:" + (getDocHeight()-230) + "px");
		}
		function jump(target){
			resize();
			var element = document.getElementById("select");
			var value = element.options[element.selectedIndex].value;
			if (value != "select") document.getElementById("frame").src = value+target;	
		}
	</script>
</head>

<body onResize="onResize()">

<h2>Choose Run</h2>
<select id="select" onchange="select()">
	<option value="select">Select</option>	
</select>
<br>
<br>
<div id="header">
	<h1>GORAP results</h1>
	reloading (F5) and/or resizing the window may solve displaying issues
</div>

<div id="nav">
	Navigation:
	<button width="30" type="button" onclick="jump('#param')">Parameter</button>
	<br>
	<button width="30" type="button" onclick="jump('#db')">Data</button>
	<br>
	<button type="button" onclick="jump('#anno')">Annotation</button>
	<br>
	<button type="button" onclick="jump('#aln')">Alignments</button>
	<br>
	<button type="button" onclick="jump('#phylo')">Phylogeny</button>
	<br>
</div>

<iframe id="frame" frameborder="0" onLoad="resize()"></iframe>

</body>

</html>

<!DOCTYPE html>
<html>

<head>
	<style> 
		.staticbox {
			float: left;
			margin: 10px;
			padding: 10px;
			width: 450px;
			overflow:auto;
		}
		.box {
			float: left;
			margin: 10px;
			padding: 10px;
		}
		html {
			display: table;
			margin: auto;
		}
		body {
			display: table-cell;			
		}
	</style>
    
    <link rel="stylesheet" href="http://www.rna.uni-jena.de/supplements/src/css/style.css" type="text/css" media="print, projection, screen" /> 

    <script type="text/javascript" src="http://www.rna.uni-jena.de/supplements/src/jquery/jquery-latest.js"></script> 
    <script type="text/javascript" src="http://www.rna.uni-jena.de/supplements/src/jquery/jquery.tablesorter.js"></script>
    <script type="text/javascript" src="http://www.rna.uni-jena.de/supplements/src/jquery/jquery.tablesorter.staticrow.min.js"></script>

    <script>
		$(document).ready(function(){ 
			$("#myID").tablesorter(); //# for id
		});   
		$(document).ready(function(){ 
			$("element").tablesorter(); //# for element
		});
		$(document).ready(function(){ 
			$(".tablesorter").tablesorter(); //.class for a class
		});  
		$(document).ready(function(){ 
			$("table.tablesorter").tablesorter(); //element.class for a specific element with class
		}); 
	</script>

</head>

<body>
<div>

<a name="param"></a>
<div style="margin:10px;padding:10px">
	<h3>Parameter</h3>
</div>

<a name="db"></a>
<div class="staticbox">
	<h3>Used data</h3>
</div>

<a name="anno"></a>
<div class="box">
	<h3>ncRNA annotation</h3>	
</div>

<a name="aln"></a>
<div class="box">
	<h3>ncRNA alignments</h3>
</div>

<a name="phylo"></a>
<div class="staticbox">
	<h3>Phylogeny SSU</h3>
</div>
<div class="staticbox">
	<h3>Phylogeny RNome</h3>
</div>

</div>
</body>

</html>