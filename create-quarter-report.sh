#!/bin/bash

declare -A libraryTypes=( ["panel"]="panel" ["exome"]="wes" ["genome-short-read"]="wgs" ["genome-long-read"]="wgs_lr" ["none"]="none" )

declare -A diseaseTypes=( ["MTB"]="oncological" ["RD"]="rare" )

declare -A submitterIds=( ["Charité"]="261101015" ["KUM"]="260914050" ["MHH"]="260320597" ["MRI"]="260913195" ["UM"]="260730161" ["UME"]="260510381" ["UMG"]="260310378" ["UKA"]="260530012" ["UKB"]="260530103" ["UKD"]="260510018" ["UKDD"]="261401030" ["UKE"]="260200013" ["UKER"]="260950567" ["UKFR"]="260832299" ["UKHD"]="260820466" ["UKJ"]="261600736" ["UKK"]="260530283" ["UKL"]="261401052" ["UKM"]="260550131" ["UKMR"]="260620431" ["UKR"]="260930608" ["UKSH"]="260102343" ["UKT"]="260840108" ["UKU"]="260840200" ["UKW"]="260960079" )

declare -A kdkIds=( ["MTB"]="KDKTUE005" ["RD"]="KDKTUE002" )

declare -A start=( ["1"]="01-01" ["2"]="04-01" ["3"]="07-01" ["4"]="10-01" )
declare -A end=( ["1"]="03-31" ["2"]="06-30" ["3"]="09-30" ["4"]="12-31" )



request(){

  curl -k \
    --cert "$CLIENT_CERT_FILE" \
    --key "$CLIENT_KEY_FILE" \
    --connect-timeout 5 \
    --max-time 20 \
    --fail --silent --show-error \
    -H "Host: $1" \
    -o "$3" \
    https://dnpm.med.uni-tuebingen.de$2
}


if [ -z "$1" ]; then
  csvSites="Charite,KUM,MHH,MRI,UKA,UKB,UKD,UKDD,UKE,UKER,UKFR,UKHD,UKJ,UKK,UKL,UKM,UKMR,UKR,UKSH,UKT,UKU,UKW,UM,UME,UMG"
else
  csvSites=$1
fi

IFS=',' read -ra sites <<< "$csvSites"

#echo -n "Use case (MTB, RD): "
#read csvuseCases
#IFS=',' read -ra useCases <<< "$csvuseCases"

#echo -n "Reporting year: "
#read year

#echo -n "Reporting quarter: "
#read quarter

useCases=("MTB" "RD")

year=2025
quarter=4


outDir="Q${quarter}_${year}"
if [ ! -d "$outDir" ]; then
  mkdir $outDir
fi

cd $outDir


getData(){
  for site in "${sites[@]}"; do

    vhost="${site,,}.dnpm.de"
 
    for useCase in "${useCases[@]}"; do
 
      reportFile="${site}_${useCase}_Report_Q${quarter}_${year}.json"
      submissionReportsFile="${site}_${useCase}_SubmissionReports_Q${quarter}_${year}.json"
        
      if [ ! -s "$reportFile" ]; then
        echo "Site $site Use Case $useCase: Getting MV Report Q$quarter $year"
  
        request $vhost "/api/${useCase,,}/peer2peer/mvh/report?quarter=${quarter}&year=${year}" $reportFile
      fi
 
      if [ ! -s "$submissionReportsFile" ]; then
        startDate="${year}-${start[${quarter}]}"
        endDate="${year}-${end[${quarter}]}"
  
        echo "Site $site Use Case $useCase: Getting SubmissionReports $startDate - $endDate"
  
        request $vhost "/api/${useCase,,}/peer2peer/mvh/submission-reports?created-after=${startDate}T00:00:00&created-before=${endDate}T23:59:59" $submissionReportsFile
      fi
 
    done
  done
}


createAppendix1(){

  headers="clinicalDataNodeId\tquarter\tyear\tsubmitterId\tnumber_of_end-to-end_tests\tnumber_of_passed_end-to-end_tests\tnumber_of_submissions_total\tnumber_of_submissions_single\tnumber_of_submissions_duo\tnumber_of_submissions_trio\tnumber_of_failed_qcs\tnumber_of_mv_consent_revocations_index\tnumber_of_research_consent_revocations_index\tnumber_of_mv_consent_revocations_not_index\tnumber_of_research_consent_revocations_not_index\tnumber_of_deletions"

for useCase in "${useCases[@]}"; do

  kdk=${kdkIds[${useCase}]}
  
  appendixFile="1-Gesamtübersicht_${kdk}_${quarter}_${year}.csv"
 
  > $appendixFile 

  echo -e "$headers" >> $appendixFile

  for site in "${sites[@]}"; do

    infile=${site}_${useCase}_Report_Q${quarter}_${year}.json
  
    if [ -s "$infile" ]; then
      echo "Processing $infile"
      
      submitter=${submitterIds[$(jq -r '.site.code' $infile)]}
      numTests=$(jq -r '.submissionTypes.elements[] | select(.key == "test") | .value.count' $infile)
      total=$(jq -r '.submissionTypes.total' $infile)
      singles=$(jq -r 'if has ("familyControlLevels") then (.familyControlLevels.elements[] | select(.key == "single-genome") | .value.count) else "0" end' $infile)
      duos=$(jq -r 'if has ("familyControlLevels") then (.familyControlLevels.elements[] | select(.key == "duo-genome") | .value.count) else "0" end' $infile)
      trios=$(jq -r 'if has ("familyControlLevels") then (.familyControlLevels.elements[] | select(.key == "trio-genome") | .value.count) else "0" end' $infile)
      
      echo -e "$kdk\t$quarter\t$year\t$submitter\t${numTests:-0}\t${numTests:-0}\t$total\t${singles:-0}\t${duos:-0}\t${trios:-0}\tN/A\tN/A\tN/A\tN/A\tN/A\tN/A" >> $appendixFile
    
    fi
  done
    
done
}


createAppendix2(){

  headers="clinicalDataNodeId\tquarter\tyear\tsubmitterId\tsubmissionType\tcoverageType\tdiseaseType\tsequenceType\tlibraryType\tdata_quality_check_passed\thas_mv_consent\thas_research_consent\tresearchConsent.noScopeJustification"

  for useCase in "${useCases[@]}"; do

    kdk=${kdkIds[${useCase}]}
    
    appendixFile="2-Datensätze_${kdk}_${quarter}_${year}.csv"
    
    if [ ! -f "$appendixFile" ]; then
    
      echo -e "$headers" >> $appendixFile

      for site in "${sites[@]}"; do

        infile=${site}_${useCase}_SubmissionReports_Q${quarter}_${year}.json
      
        if [ -s "$infile" ]; then

          echo "Processing $infile"

          # See: https://starkandwayne.com/blog/bash-for-loop-over-json-array-using-jq/index.html
          for entry in $(jq -r '.entries[] | @base64' $infile); do
          
            _jq(){
              echo ${entry} | base64 --decode | jq -r "${1}"
            }
          
            submitter=${submitterIds[$(_jq '.site.code')]}
            submissionType=$(_jq '.type')
            coverageType=$(_jq '.healthInsuranceType')
            diseaseType=${diseaseTypes[$(_jq '.useCase')]}
            libraryType=${libraryTypes[$(_jq '.sequencingType')]:-none}
            seqType=$(_jq '(.sequenceTypes? // []) as $arr | if ($arr | length) > 0 then ($arr | join(";")) else "N/A" end')
            qcPassed="yes"  # Invalid submissions are denied upon upload in DIP, so any created SubmissionReport implies passed QC
            has_mv_consent=$(_jq '.consentStatus["mv-consent"]? // false | if . then "yes" else "no" end')
            has_research_consent=$(_jq '.consentStatus["research-consent"]? // false | if . then "yes" else "no" end')
            reasonResearchConsentMissing=$(_jq '.reasonResearchConsentMissing? // "N/A"')
          
            echo -e "$kdk\t$quarter\t$year\t$submitter\t$submissionType\t$coverageType\t$diseaseType\t$seqType\t$libraryType\t$qcPassed\t$has_mv_consent\t$has_research_consent\t$reasonResearchConsentMissing" >> $appendixFile
          
          done

	fi
      done
    
    fi

  done
}

#getData
#createAppendix1
createAppendix2


