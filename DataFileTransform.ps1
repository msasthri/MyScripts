#_________________________________________________________________________________________________________________
# NAME           : DATAFILETRANSFORM.PS1
# DESCRIPTION    : POWERSHELL SCRIPT TO LOOK DESIRED FILE, TRANSFORM AND LOAD
# CREATED BY     : MOHANRAJ CHANDRASEKAR
# CREATED ON     : 05/15/2014
# SCRIPT VERSION : 0.6            POWERSHELL VERSION : 3.0
# 
# CHANGE HISTORY : 0.1 - 05/15/2014 - Initial Version
#                : 0.2 - 05/29/2014 - Reading parameters from Config file and processing
#                : 0.3 - 06/02/2014 - Add all features of Information System, included error handling except SFTP
#                : 0.4 - 06/11/2014 - Handler for DateTime stamp in data files and included
#                : 0.5 - 06/14/2014 - Invalid batch files handled
#                : 0.6 - 06/23/2014 - Archiving Header files included
#_________________________________________________________________________________________________________________

#Configuration File, All Parameters defined here
$ConfigFile="C:\MyScripts\MIS_FIN_TD_CONFIG_DROP6.XML"

#Defining parameter variables for Shell script
[string]$ArchiveFolder = ''
[string]$ProcessFolder = ''
[string]$LandingFolder = ''
[string]$MISException = ''
[int]$DataFileCounter = 0
[string]$LogContent = ""
[string]$BatchID = '0000'
[xml]$Configuration = ''
[string]$PatternExtension = '*.TXT'
[array]$ControlFileContent = @()


#region - Validate configuration file
    Try 
    {
        (Get-Date -UFormat "%Y-%m-%d %H:%M:%S") + ' - Attempting to load configuration file to PowerShell'

        [xml]$Configuration = Get-Content $ConfigFile -ErrorAction Stop
    
        [string]$ProcessFolder = $Configuration.Configurations.Dir.ProcessFolder.value.ToString()
	    [string]$ArchiveFolder = $Configuration.Configurations.Dir.ArchiveFolder.value.ToString()
	    [string]$LandingFolder = $Configuration.Configurations.Dir.LandingFolder.value.ToString()
        [string]$CTRLFilePattern = $Configuration.Configurations.Dir.ControlFilePattern.value.ToString()
        [string]$CTRLFileFilter = $CTRLFilePattern + $PatternExtension

        '    Primary Process Folder Path : ' + $ProcessFolder
	    '    Archive Folder Path : ' + $ArchiveFolder
	    '    Landing Zone Path : ' + $LandingFolder

        If (!$ProcessFolder) 
        { 
            $MISException = 'MIS Exception: Invalid Configuration File'
            Throw     
        }

            #region - Get Batch ID and TimeStamp for the subject area and create empty control file

        (Get-Date -UFormat "%Y-%m-%d %H:%M:%S") + ' - Calculating Batch ID and TimeStamp for the New batch...'
    
        $ControlFiles = Get-ChildItem -Path $ArchiveFolder  -Filter $CTRLFileFilter | Sort-Object BaseName 
        IF ($ControlFiles) 
        {
            ForEach ($BatchNo in ($ControlFiles.BaseName).TrimStart($CTRLFilePattern).substring(0,4) ) { 
                $NewBatchNo = 1 + $BatchNo
            }
            $BatchID = ('0000' + $NewBatchNo).Substring(('0000'+$NewBatchNo).Length - 4)
        }
        ELSE
        {
            $BatchID = '0001'
        }
        
        $TimeStamp = Get-Date -UFormat "%Y%m%d%H%M%S"
        "    BatchID : " + $BatchID
        "    TimeStamp : " + $TimeStamp
    }
    
    Catch [System.Exception] 
    {
      write-host $MISException -ForegroundColor Red
      write-host "System Exception: $($_.Exception.Message)" -ForegroundColor Red
      exit
    }
#endregion

#region - Check Data file presence

    Try 
    {
        (Get-Date -UFormat "%Y-%m-%d %H:%M:%S") + ' - Checking Data File Availability'
        [array]$FilesToProcess = @()
        ForEach( $FileList in $Configuration.Configurations.FileList) { 
	        $TestFilePath = $FileList.DFilePath
	        $TestFilePrefix = $FileList.FileName
            $TestFilePattern = $TestFilePrefix + '*'+ $PatternExtension
            $IsLastFile = $FileList.IsLast

            [string]$Delimited =$FileList.Delimited
            $Header =$FileList.Header
	        $UpdCol=$FileList.UPDCol
	        $DelCol=$FileList.DELCol
            if ($Delimited) 
            {
                $IsDelimited = 1
                [string]$Delimiter = $Delimited
            }
            ELSE
            {
                $IsDelimited = 0
                $Delimiter = ''
            }

            $TestFileInstances = Get-ChildItem -Path $TestFilePath  -Filter $TestFilePattern | Sort-Object BaseName | Select-Object -first 1
            IF ($TestFileInstances) 
            {
                ForEach ($TestFileInstance in $TestFileInstances.BaseName) { 
                    #$TestFileInstance.Replace($TestFilePrefix+'_','')  
                    '    Earliest instance of '+ $TestFilePrefix +' is '+ $TestFileInstance + '.TXT'
                    $DataFile = $TestFilePath+$TestFileInstance+'.TXT'
                    $FilesToProcess = $FilesToProcess + @($DataFile)

                    '        Calculating Records (Total, New and Deleted) count and caching in memory'
                    
                    #Calculate record counts
                    if ($IsDelimited -eq 0) {
                        $res = Get-Content $DataFile  
                        $TotCnt = $res.Count - $hdr
                        [int]$DelCnt = 0
                        [int]$UpdCnt = 0

                        If(!$DelCol) 
                        {
                            $NewCnt = $TotCnt
                        }
                        ELSE
                        {
                            Foreach($Records in $res)
                            {
                                if($Ctr -ge $hdr) {
                                    $DataRecord = $Records.Substring($DelCol,1)
                                    if($DataRecord -eq 'X') {
                                        $DelCnt = $DelCnt + 1 
                                    }
                                }
                            $Ctr = $Ctr + 1
                            }  
                        $NewCnt = $TotCnt - $DelCnt  
                        }

                    }
                    ELSE
                    {
                        $file = Import-Csv $DataFile -Delimiter '|'
                        $fields = $file[0].psobject.properties |% {$_.name}

                        $TC = $file | Measure-Object $fields[1]
                        [int]$TotCnt = $TC.Count
                        
                        #region - Update column count not required
                                # This feature not supported by BW Data files - Update counts Default to 0
                                #[int]$UpdCol = 0
                                #if ($UpdCol -eq 0) {$UpdCnt = 0} ELSE {
                                #$UC = $file | Measure-Object $fields[$UpdCol] -Sum 
                                #$UpdCnt = $UC.Sum
                                #$NewCnt = $TotCnt - $UpdCnt
                                #}
                            #endregion

                        [int]$UpdCnt = 0
                        if ($DelCol -eq 0) {
                            $DelCnt = 0
                            $NewCnt = $TotCnt
                        } 
                        ELSE 
                        {
                            $DC = $file | Measure-Object $fields[$DelCol] -character -line -word
                            [int]$DelCnt = $DC.Characters
                            $NewCnt = $TotCnt - $DelCnt
                        }
                    }

                    '        Total record   : '+$TotCnt
                    '        New record     : '+$NewCnt
                    '        Updated record : 0 (default)'
                    '        Deleted record : '+$DelCnt
                    $DataFileCounter = $DataFileCounter + 1
                    $CtrlCnt = $TestFileInstance.Substring(0,$TestFileInstance.Length-14)+$BatchID+$TimeStamp+'.TXT' +"|" + $TotCnt+"|"+$NewCnt+"|"+$UpdCnt+"|"+$DelCnt+"|"+$DataFileCounter
                    $ControlFileContent = $ControlFileContent + @($CtrlCnt)
                } 
            } 
            ELSE { $MISException = 'MIS Exception: An instance of ' + $TestFilePrefix + ' couldn''t be found'
                Throw 
            }

            #Compare Instance of Last file with rest of the files in Processing folder
            IF($IsLastFile) {
                
                'Last File to Process : ' + $TestFileInstance + '.TXT'
                [bigint]$LatestInBatch = $TestFileInstance.substring($TestFileInstance.length - 14, 14)
                $NextBatchFiles = Get-ChildItem -Path $TestFilePath -name -Include 'ECC_*.TXT' -Exclude $FilesToProcess.replace($TestFilePath,'') | Sort-Object BaseName 
                IF ($NextBatchFiles) {
                    ForEach ($NextFile in $NextBatchFiles) {
                        IF ($NextFile.length -gt 18) {
                            [bigint]$EarliestInFolder = $NextFile.substring($NextFile.length - 18, 14)
                            IF ($LatestInBatch -gt $EarliestInFolder) { $MISException = 'MIS Exception: Batch validation failed, file(s) missing for the batch when next batch is in queue. This could be due to data file(s) being created manually'
                                Throw
                            }
                        }
                    }    
                }
                ELSE {
                }
            }
            
        }

         (Get-Date -UFormat "%Y-%m-%d %H:%M:%S") + ' - Files Renamed from BW to EDW format and compress'
        ForEach ($FileToProcess in $FilesToProcess) {
            [string]$DataFolder = $FileToProcess.Substring(0,$FileToProcess.IndexOf('ECC_')) 
            [string]$BWFileName = $FileToProcess.Substring($FileToProcess.IndexOf('ECC_')) 
            [int]$SuffixLength = $BWFileName.Length - 18
            [string]$EDWFileName = $BWFileName.Substring(0,$SuffixLength)+$BatchID+$TimeStamp+'.TXT'
            
            [string]$BWFullName = $DataFolder + $BWFileName
            [string]$EDWFullName = $DataFolder + $EDWFileName
            [string]$BWConfigName = $DataFolder +'S_'+ $BWFileName
            
            if ((Test-Path $BWConfigName)) {
                Move-Item $BWConfigName $ArchiveFolder
                '    BW header file S_'+ $BWFileName + ' archived in '+$ArchiveFolder
            }
            ELSE {
                '    BW header file S_'+ $BWFileName + ' missing'
            }


            Move-Item $BWFullName $EDWFullName
            '    BW File: '+$BWFileName+' renamed to EDW File: '+$EDWFileName
           

            '    Compressing '+$EDWFileName+' to '+$EDWFileName+'.gz'
            & 'c:\gzip\gzip.exe' $EDWFullName

            $EDWGZName = $DataFolder + $EDWFileName +'.gz'
            '    SFTP: Transfering '+$EDWFileName+'.gz to EDW Landing zone'
            
            #Instead of copy use SFTP
            #Copy-Item  $EDWGZName $LandingFolder
            # Create txt file (batch .txt)
            $SFTPBatchCommands = $ProcessFolder+'\SFTPTempCmds.txt'
            "PUT " + $EDWGZName + $LandingFolder+$EDWFileName +'.gz' | Set-Content $SFTPBatchCommands -Encoding UTF8
            #Execute the sftp command
            sftp -B $SFTPBatchCommands EYUA\D.MERFT.1@10.149.104.177


            #Archive data files
            Move-Item  $EDWGZName $ArchiveFolder


            }
        (Get-Date -UFormat "%Y-%m-%d %H:%M:%S") + ' - Archiving all files'

        $ControlFileName = $CTRLFilePattern + $BatchID  + $TimeStamp + '.TXT'
        $ControlFileFullName = $ProcessFolder+"\"+$ControlFileName
        
        "FileName|TotalRowCount|NewRowCount|UpdateRowCount|DeleteRowCount|LineNumber" | Set-Content $ControlFileFullName -Encoding UTF8
        $ControlFileContent | Add-Content $ControlFileFullName -Encoding UTF8
        
        Copy-Item  $ControlFileFullName $LandingFolder
        
        #Archive Control file
        Move-Item  $ControlFileFullName $ArchiveFolder


    }
    Catch [System.Exception] 
    {
      write-host $MISException -ForegroundColor Red
      write-host "System Exception: $($_.Exception.Message)" -ForegroundColor Red
      exit
    }
#endregion
