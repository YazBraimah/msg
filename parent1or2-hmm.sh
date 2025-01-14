#!/usr/bin/env sh

usage () {
    echo usage: `basename $0` -b barcodes -s samdir -o outdir -R Routdir -p parent1 -q parent2 -i indiv -c chroms -w bwaalg -v use_filter_hmmdata_pl -k repeat_threshold
    exit 2
}

die () {
    echo "$1"
    exit ${2:-1}
}

src=$(dirname $0)

while getopts "a:b:c:e:f:g:h:i:j:k:l:m:n:o:p:q:r:R:s:S:t:u:v:w:x:y:z:" opt
do 
  case $opt in
      a) recRate=$OPTARG ;;
      b) barcodes=$OPTARG ;;
      c) chroms=$OPTARG ;;
      e) usestampy=$OPTARG ;;
      f) deltapar1=$OPTARG ;;
      g) deltapar2=$OPTARG ;;
      i) indiv=$OPTARG ;;
      j) pepthresh=$OPTARG ;;
      k) repeatthresh=$OPTARG ;;
      l) read_length=$OPTARG ;;
      m) gff_thresh_conf=$OPTARG ;;
      n) max_mapped_reads=$OPTARG ;;
      o) outdir=$OPTARG ;;
      p) parent1=$OPTARG ;;
      q) parent2=$OPTARG ;;     
      r) rfac=$OPTARG ;;
      R) Routdir=$OPTARG ;;
      s) samdir=$OPTARG ;;
      S) samtools=$OPTARG ;;
      t) theta=$OPTARG ;;
      u) one_site_per_contig=$OPTARG ;;
      v) filter_hmmdata_pl=$OPTARG ;;
      w) bwaalg=$OPTARG ;;
      x) sexchroms=$OPTARG ;;
      y) chroms2plot=$OPTARG ;;
      z) priors=$OPTARG ;; 
      
      *) usage ;;
  esac
done
shift $(($OPTIND - 1))

[ -n "$samdir" ] && [ -n "$outdir" ] && [ -n "$barcodes" ] && [ -n "$parent1" ] && [ -n "$parent2" ] && [ -n "$indiv" ] && [ -n "$samtools" ] || usage
[ -n "$Routdir" ] || usage
[ -d $outdir ] || mkdir -p $outdir

[ -n "$deltapar1" ] || deltapar1=.01
[ -n "$deltapar2" ] || deltapar2=$deltapar1
[ -n "$recRate" ] ||   recRate=0
[ -n "$rfac" ] ||      rfac=.000001
[ -n "$read_length" ] || read_length=100

date
echo "version 0.0"

#plate=$(echo $indiv | perl -pe 's/^indiv([A-Z][0-9][0-9]?)_.+/$1/')
#sex=$(perl -ne "print if /[ACGT]+\t$plate\t/" $barcodes | cut -f4)
#Barcode file structure: barcode indiv_id plate_id sex
#Column delimiter should still be tabs, but some text editors misinterpret the tab key as a fixed number of spaces.
#Thus we handle the general case of the delimiter being one or more whitespace characters (i.e. \s+).
#We also handle the general case for the individual's ID, as just being "indiv" followed by one or more non-whitespace characters.
indivnumber=$(echo $indiv | perl -pe 's/^indiv(\S+)_.+/$1/')
sex=$(perl -ne "print if /^[ACGT]+\s+$indivnumber\s+/" $barcodes | awk ' { print $4; } ')
plate=$(perl -ne "print if /^[ACGT]+\s+$indivnumber\s+/" $barcodes | awk ' { print $3; } ')
[ -z "$sex" ] && sex=female

echo ; echo ; echo "---------------------------------------------------------------------" ; echo

echo "Processing INDIVIDUAL $indiv PLATE $plate SEX $sex DELTA $deltapar1,$deltapar2 RECRATE $recRate RFAC $rfac"

indivdir=$outdir/$indiv
[ -d $indivdir ] || mkdir -p $indivdir

[ -e $indivdir/aln_${indiv}_par1-filtered.sam ] || [ -e $indivdir/aln_${indiv}_par1-filtered.sam.gz ] && \
    [ -e $indivdir/aln_${indiv}_par2-filtered.sam ] || [ -e $indivdir/aln_${indiv}_par2-filtered.sam.gz ] || {

    #If $max_mapped_reads is specified, truncate sam files (preserving headers if any)
    if [ "$max_mapped_reads" -gt 0 ]
    then
        echo "Truncating sam files ${samdir}/aln_${indiv}_par1.sam ${samdir}/aln_${indiv}_par2.sam"
        if [ -e $samdir/aln_${indiv}_par1.sam ]
        then
            echo "Truncating ${samdir}/aln_${indiv}_par1.sam"
            #copy original
            cp ${samdir}/aln_${indiv}_par1.sam ${samdir}/aln_${indiv}_par1-all-reads.sam
            #find headers if any and start replacement file with them.  (SAM docs say this regex finds headers ...)
            grep -P "^@[A-Za-z][A-Za-z]\t" ${samdir}/aln_${indiv}_par1.sam > ${samdir}/aln_${indiv}_par1-temp.sam
            #Get remaining non header portion of file and add to replacement file
            grep -P -v -m $max_mapped_reads "^@[A-Za-z][A-Za-z]\t" ${samdir}/aln_${indiv}_par1.sam >> ${samdir}/aln_${indiv}_par1-temp.sam
            #replace original
            mv ${samdir}/aln_${indiv}_par1-temp.sam ${samdir}/aln_${indiv}_par1.sam
        fi
        if [ -e $samdir/aln_${indiv}_par2.sam ]
        then
            echo "Truncating ${samdir}/aln_${indiv}_par2.sam"
            #copy original
            cp ${samdir}/aln_${indiv}_par2.sam ${samdir}/aln_${indiv}_par2-all-reads.sam
            #find headers if any and start replacement file with them.  (SAM docs say this regex finds headers ...)
            grep -P "^@[A-Za-z][A-Za-z]\t" ${samdir}/aln_${indiv}_par2.sam > ${samdir}/aln_${indiv}_par2-temp.sam
            #Get remaining non header portion of file and add to replacement file
            grep -P -v -m $max_mapped_reads "^@[A-Za-z][A-Za-z]\t" ${samdir}/aln_${indiv}_par2.sam >> ${samdir}/aln_${indiv}_par2-temp.sam
            #replace original
            mv ${samdir}/aln_${indiv}_par2-temp.sam ${samdir}/aln_${indiv}_par2.sam
        fi
        if [ -e $samdir/aln_${indiv}_par1.sam.gz ]
        then
            echo "Truncating ${samdir}/aln_${indiv}_par1.sam.gz"
            #copy original
            cp ${samdir}/aln_${indiv}_par1.sam.gz ${samdir}/aln_${indiv}_par1-all-reads.sam.gz
            #find headers if any and start replacement file with them.  (SAM docs say this regex finds headers ...)
            zgrep -P "^@[A-Za-z][A-Za-z]\t" ${samdir}/aln_${indiv}_par1.sam.gz > ${samdir}/aln_${indiv}_par1-temp.sam
            #Get remaining non header portion of file and add to replacement file
            zgrep -P -v -m $max_mapped_reads "^@[A-Za-z][A-Za-z]\t" ${samdir}/aln_${indiv}_par1.sam.gz >> ${samdir}/aln_${indiv}_par1-temp.sam
            #recompress
            gzip ${samdir}/aln_${indiv}_par1-temp.sam
            #replace original
            mv ${samdir}/aln_${indiv}_par1-temp.sam.gz ${samdir}/aln_${indiv}_par1.sam.gz
        fi
        if [ -e $samdir/aln_${indiv}_par2.sam.gz ]
        then
            echo "Truncating ${samdir}/aln_${indiv}_par2.sam.gz"
            #copy original
            cp ${samdir}/aln_${indiv}_par2.sam.gz ${samdir}/aln_${indiv}_par2-all-reads.sam.gz
            #find headers if any and start replacement file with them.  (SAM docs say this regex finds headers ...)
            zgrep -P "^@[A-Za-z][A-Za-z]\t" ${samdir}/aln_${indiv}_par2.sam.gz > ${samdir}/aln_${indiv}_par2-temp.sam
            #Get remaining non header portion of file and add to replacement file
            zgrep -P -v -m $max_mapped_reads "^@[A-Za-z][A-Za-z]\t" ${samdir}/aln_${indiv}_par2.sam.gz >> ${samdir}/aln_${indiv}_par2-temp.sam
            #recompress
            gzip ${samdir}/aln_${indiv}_par2-temp.sam
            #replace original
            mv ${samdir}/aln_${indiv}_par2-temp.sam.gz ${samdir}/aln_${indiv}_par2.sam.gz
        fi
    fi

    echo "Extracting reference allele information from SAM files for $indiv ($parent1 and $parent2)"
    echo "python $src/extract-ref-alleles.py -i $indiv -d $samdir -o $indivdir --parent1 $parent1 --parent2 $parent2 --chroms $chroms --bwa_alg $bwaalg --use_stampy $usestampy --repeat_threshold $repeatthresh"
    python $src/extract-ref-alleles.py -i $indiv -d $samdir -o $indivdir --parent1 $parent1 --parent2 $parent2 --chroms $chroms --bwa_alg $bwaalg --use_stampy $usestampy --repeat_threshold $repeatthresh || {
        echo "Error during extract-ref-alleles.py for $indiv"
    }
   
}

echo "Creating pileup for $indiv"
echo "bash $src/make-pileups.sh -i $indiv -d $indivdir -p $parent1 -q $parent2 -S ${samtools} 2>&1 | grep -vF 'deleted'"
bash $src/make-pileups.sh -i $indiv -d $indivdir -p $parent1 -q $parent2 -S ${samtools} 2>&1 | grep -vF 'deleted'

#Check for existence of the pileup files:
if [[ -z $(ls $indivdir | grep '\.pileup') ]]; then
   echo "Error: make-pileups.sh failed to create any pileup files for $indiv."
   exit 3
fi


echo "Writing HMM input data for $indiv"
cmd="Rscript $src/write-hmm-data.R -i $indiv -d $indivdir -c $chroms"
echo $cmd
exec 3>&1; exec 1>&2; echo $cmd; exec 1>&3 3>&-
$cmd || {
    echo "Error during write-hmm-data.R for $indiv"
}

#Check for existence of the hmmdata files:
if [[ -z $(ls $indivdir | grep '\.hmmdata') ]]; then
   echo "Error: write-hmm-data.R failed to create any hmmdata files for $indiv."
   exit 4
fi

#Filter the hmmdata file before fit-hmm.R if requested:
if [[ "$filter_hmmdata_pl" -gt 0 ]]; then
   echo "Filtering hmmdata file for ancestry informative markers within 1 read of each other."
   for hmmdatafile in ${indivdir}/*.hmmdata #There should be an .hmmdata file for each scaffold
      do
      if [[ ! $hmmdatafile =~ ".filtered.hmmdata" ]]; then #Make sure we don't enter an infinite loop due to the wildcard in the for loop
         cmd="perl $src/filter_hmmdata.pl --read_length $read_length ${hmmdatafile}"
         exec 3>&1; exec 1>&2; echo $cmd; exec 1>&3 3>&-
         echo $cmd
         $cmd || echo "Error during filtering of hmmdata file ${hmmdatafile} for $indiv"
      fi
   done
   #If we're filtering the hmmdata file, set one_site_per_contig to 0:
   one_site_per_contig=0
fi


echo "Fitting HMM for $indiv"
Rindivdir=$Routdir/$indiv
[ -d $Rindivdir ] || mkdir -p $Rindivdir
cmd="Rscript $src/fit-hmm.R -d $outdir -i $indiv -s $sex -o $Routdir -p $deltapar1 -q $deltapar2 -a $recRate -r $rfac -c $chroms -x $sexchroms -y $chroms2plot -z $priors -t $theta -g $gff_thresh_conf -u $one_site_per_contig -j $pepthresh -v $filter_hmmdata_pl"

exec 3>&1; exec 1>&2; echo $cmd; exec 1>&3 3>&-
echo $cmd
$cmd || {
    echo "Error during fit-hmm.R for $indiv"
}
echo "Done $indiv"
# block-22 ends here
