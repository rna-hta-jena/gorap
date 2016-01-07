#!/bin/bash
retool=$1

if [[ $retool = '' ]]; then
	echo 'Do you forgot to add a tool name as parameter? Or'
	read -p 'do you want to recompile all tools [y|n] ' in
	if [[ $in = 'y' ]] || [[ $in = 'Y' ]]; then		
		retool='all'
	else 
		read -p 'Please enter the correct tool name as used in '$GORAP'/<toolname-version> or hit return to exit' retool
		if [[ "$retool" = '' ]]; then
			echo 'Recompilation aborted...'
			exit
		fi
	fi
fi

pwd=$PWD
mkdir -p  $GORAP

download () {
	if [[ ! -d $GORAP/$tool ]] && [[ $ex -eq 0 ]]; then
		echo 'Downloading '$tool	
		wget -T 10 -N www.rna.uni-jena.de/supplements/gorap/$tool.tar.gz
		if [[ $? -gt 0 ]]; then
			echo $tool' installation failed'
			exit 1
		fi 
		echo 'Extracting '$tool
		tar -xzf $tool.tar.gz -C $GORAP
		rm $tool.tar.gz
	fi
}

cd $pwd
tool='RAxML-7.4.2'
if [[ $tool = $retool ]] || [[ $retool = 'all' ]]; then	
	if [[ -d $GORAP/$tool ]]; then
		if [[ $OSTYPE == darwin* ]]; then 
			cpu=$(sysctl -n machdep.cpu.brand_string | egrep '(i5|i7)' | wc | awk '{print $1}')		
		else
			cpu=$(grep -m 1 ^model\ name /proc/cpuinfo | egrep '(i5|i7)' | wc | awk '{print $1}')
		fi	

		if [[ $cpu -eq 0 ]]; then
			cd $GORAP/$tool
			make -f Makefile.SSE3.PTHREADS.gcc
			if [[ $? -gt 0 ]]; then				
				exit 1
			fi 
			mkdir -p bin 
			mv raxmlHPC-PTHREADS-SSE3 bin/raxml 						
		else
			cd $GORAP/$tool 
			make -f Makefile.AVX.PTHREADS.gcc 
			if [[ $? -gt 0 ]]; then				
				exit 1
			fi
			mkdir -p bin 
			mv raxmlHPC-PTHREADS-AVX bin/raxml
		fi
	else 
		echo 'Please run install_tools.sh first, then try again'
	fi
fi

cd $pwd
tool='mafft-7.017-with-extensions'
if [[ $tool = $retool ]] || [[ $retool = 'all' ]]; then
	if [[ -d $GORAP/$tool ]]; then
		cd $GORAP/$tool/core
		make
		if [[ $? -gt 0 ]]; then				
			exit 1
		fi
		make install
		make clean
	else 
		echo 'Please run install_tools.sh first, then try again'
	fi
fi

tool='infernal-1.1rc2'
infernal=$tool
if [[ $tool = $retool ]] || [[ $retool = 'all' ]]; then
	if [[ -d $GORAP/$tool ]]; then
		cd $GORAP/$tool
		./configure --prefix=`pwd`
		make
		if [[ $? -gt 0 ]]; then				
			exit 1
		fi
		make install
		make clean

		glibc=$(ldd --version | head -n 1 | awk '{split($NF,a,"."); print a[2]}')
		if [[ $? -gt 0 ]]; then
			glibc=0
		fi
		if [[ $glibc -lt 14 ]]; then
			tool='glibc-2.21'
			ex=0
			download
			
			cd $GORAP/$tool
			mkdir -p build
			cd build
			../configure --prefix=$GORAP/$infernal/easel
			make
			if [[ $? -gt 0 ]]; then				
				exit 1
			fi
			make install
			make clean

			cd $GORAP/$infernal/easel
			cp -r include/* .
			
			./configure --prefix=$GORAP/$infernal
			sed -i '/^CFLAGS/ c\CFLAGS = -O3 -fomit-frame-pointer -fstrict-aliasing -pthread -fPIC -I. -I..' Makefile							
			make
			if [[ $? -gt 0 ]]; then				
				exit 1
			fi
			make install
			make clean
		else
			cd $GORAP/$infernal/easel
			./configure --prefix=$GORAP/$infernal
			make 
			if [[ $? -gt 0 ]]; then				
				exit 1
			fi
			make install 
			make clean
		fi

	else 
		echo 'Please run install_tools.sh first, then try again'
	fi
fi

tool='esl-alimerge'
infernal='infernal-1.1rc2'
if [[ $tool = $retool ]] || [[ $retool = 'all' ]]; then
	if [[ -d $GORAP/$infernal ]]; then

		glibc=$(ldd --version | head -n 1 | awk '{split($NF,a,"."); print a[2]}')
		if [[ $? -gt 0 ]]; then
			glibc=0
		fi
		if [[ $glibc -lt 14 ]]; then
			tool='glibc-2.21'
			ex=0
			download
			
			cd $GORAP/$infernal
			mkdir -p build
			cd build
			../configure --prefix=$GORAP/$infernal/easel
			make
			if [[ $? -gt 0 ]]; then				
				exit 1
			fi
			make install
			make clean

			cd $GORAP/$infernal/easel
			cp -r include/* .
			
			./configure --prefix=$GORAP/$infernal
			sed -i '/^CFLAGS/ c\CFLAGS = -O3 -fomit-frame-pointer -fstrict-aliasing -pthread -fPIC -I. -I..' Makefile							
			make
			if [[ $? -gt 0 ]]; then				
				exit 1
			fi
			make install
			make clean
		else
			cd $GORAP/$infernal/easel
			./configure --prefix=$GORAP/$infernal
			make 
			if [[ $? -gt 0 ]]; then				
				exit 1
			fi
			make install 
			make clean
		fi
	else 
		echo 'Please run install_tools.sh first, then try again'
	fi
fi

tool='infernal-1.0'
if [[ $tool = $retool ]] || [[ $retool = 'all' ]]; then
	if [[ -d $GORAP/$tool ]]; then		
		cd $GORAP/$tool
		./configure --prefix=`pwd` 
		make
		if [[ $? -gt 0 ]]; then				
			exit 1
		fi
		make install
		make clean
	else 
		echo 'Please run install_tools.sh first, then try again'
	fi
fi

tool='rnabob-2.2'
if [[ $tool = $retool ]] || [[ $retool = 'all' ]]; then
	if [[ -d $GORAP/$tool ]]; then			
		cd $GORAP/$tool
		make
		if [[ $? -gt 0 ]]; then				
			exit 1
		fi
		make install
		make clean
	else 
		echo 'Please run install_tools.sh first, then try again'
	fi
fi

tool='ncbi-blast-2.2.27+'
if [[ $tool = $retool ]] || [[ $retool = 'all' ]]; then
	if [[ -d $GORAP/$tool ]]; then		
		cd $GORAP/$tool
		./configure --without-debug --with-strip --with-mt --with-build-root=`pwd`
		cd $GORAP/$tool/src
		make
		if [[ $? -gt 0 ]]; then				
			exit 1
		fi
		make all_r
		if [[ $? -gt 0 ]]; then				
			exit 1
		fi
		make clean
	else 
		echo 'Please run install_tools.sh first, then try again'
	fi
fi

tool='tRNAscan-SE-1.3.1' 
if [[ $tool = $retool ]] || [[ $retool = 'all' ]]; then
	if [[ -d "$GORAP/$tool" ]]; then
		cd $GORAP/$tool
		make
		if [[ $? -gt 0 ]]; then				
			exit 1
		fi
		make install
		make clean
	else 
		echo 'Please run install_tools.sh first, then try again'
	fi
fi

tool='samtools-0.1.19'
samtool=$tool
if [[ $tool = $retool ]] || [[ $retool = 'all' ]]; then
	if [[ -d "$GORAP/$tool" ]]; then
		tool='zlib-1.2.8'		
		ex=0
		download				
		
		cd $GORAP/$tool 
		./configure --prefix=$GORAP/$samtool				
		make
		if [[ $? -gt 0 ]]; then				
			exit 1
		fi
		make install
		make clean
		
		tool='ncurses-5.9'
		ex=0
		download
		
		cd $GORAP/$tool  
		./configure --prefix=$GORAP/$samtool
		make
		if [[ $? -gt 0 ]]; then				
			exit 1
		fi
		make install
		make clean

		cd $GORAP/$samtool		
		cp -r include/* .
        cp -r lib/* .                
		make 2>> $pwd/install.log >> $pwd/install.log
		if [[ $? -gt 0 ]]; then				
			exit 1
		fi                       
		mkdir -p bin 
		cp samtools bin/samtools
	else 
		echo 'Please run install_tools.sh first, then try again'		
	fi
fi

tool='hmmer-2.3.2'
if [[ $tool = $retool ]] || [[ $retool = 'all' ]]; then	
	if [[ -d $GORAP/$tool ]]; then
		cd $GORAP/$tool
		./configure --enable-threads --enable-lfs --prefix=`pwd` 
		make
		if [[ $? -gt 0 ]]; then				
			exit 1
		fi
		make install
		make clean
	else 
		echo 'Please run install_tools.sh first, then try again'
	fi
fi
