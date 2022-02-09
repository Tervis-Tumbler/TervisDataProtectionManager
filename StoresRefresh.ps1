################################################################################
# Name: RestoreSQLDB.ps1                                                       #
# Version: 1.04                                                                #
# Description: This Script Will Restore The Latest Express Full Backup Of      #
# A Database Originating From A Standalone Or Clustered 'SQL Server A' To      #
# A Standalone 'SQL Server B'.                                                 #
# The Database Can Be Renamed On The Destination SQL Server.                   #
# The File Paths Of The MDF & LDF Files Can Be Changed Too.                    #
# The $PerformRestore Var Must Be Set To $true To Actually Perform The Restore #
# This Script Requires DPM Remote Administration Tools (CLI) Are Installed.    #
# Version Modifications:                                                       #
#                                                                              #
################################################################################
#To Sign This Script Run These Commands Separately From PS After Requesting A CodeSigning Certificate
#$Certificate = Get-ChildItem cert:\CurrentUser\My -Codesign
#Set-AuthenticodeSignature ".\RestoreSQLDB.ps1" -Certificate $Certificate
#Example - Run From CMD Line
#C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NonInteractive -NoLogo -File "<PATHTOFILE>\RestoreSQLDB.ps1"
#Static Variables

### $DatabasesToRestore is in the following format
### "DPM protection Group","Source (Production) DB name","Source (production) System","Destination system to restore to","Destination DB name"

    $DPMServer = "inf-scdpmsql01.tervis.prv" #Name Of DPM Server Prtotecting SQL DB
    $DatabasesToRestore = @("Stores-Osprey_Store","OspreyStore1","1010osbo3-pc","dlt-rmsbo1","OspreystoreDB"),
                           ("Stores-Charleston","Charleston","3002chbo-pc","dlt-rmsbo3","Charleston"),
			               ("Stores-Osprey_Store","OspreyStore1","1010osbo3-pc","eps-rmsbo1","OspreystoreDB"),
                           ("Stores-Orange_Beach","OrangeBeachStore","3008OBBO2-pc","eps-rmsbo2","OrangeBeachDB"),
                           ("Stores-Charleston","Charleston","3002chbo-pc","eps-rmsbo3","Charleston")
Import-Module DataProtectionManager        
Connect-DPMServer $DPMServer; #Conenct To DPM Server


$DatabasesToRestore | % {

############################################################################

    $ProtectionGroupSQLStr = $_[0]
    $SQLDatabaseName = $_[1]
    $SourceServerName = $_[2] #If Standalone SQL Then Should Be In The Format <SERVERNAME> Or <SERVERNAME>\<INSTANCENAME> If Named Instance
    $DestinationServerName = $_[3] #Name Of Server That DB Will Be Restored To - If Named Instance Then Should Be In The Format <SERVERNAME>\<INSTANCENAME>
    $DestinationDatabaseName = $_[4] #Name Of The Database That Will Be Created On $DestinationServerName
    $DestinationMDFPath = "C:\Program Files\Microsoft SQL Server\MSSQL10_50.MSSQLSERVER\MSSQL\DATA" #Check - Dependent On The Restore Server
    $DestinationLDFPath = "C:\Program Files\Microsoft SQL Server\MSSQL10_50.MSSQLSERVER\MSSQL\DATA" #Check - Dependent On The Restore Server
############################################################################
    $PerformRestore = $true #$true To Actually Do Restore $false
    $LoggingLogName = "Windows PowerShell" #Event Log To Log Errors To
    $LoggingSource = "PowerShell" #Event Source To Log As
    $LoggingEventID = "65535" #Event Log ID To Use
#It Begins!!!!
#    Import-Module DataProtectionManager        
#    Connect-DPMServer $DPMServer; #Conenct To DPM Server
	

    #Get PG Object Named $ProtectionGroupSQLStr & Store As A Var
    $ProtectionGroupSQLObj = Get-ProtectionGroup $DPMServer | Where-Object { $_.FriendlyName -eq $ProtectionGroupSQLStr} 
    
    #Get DataSource With Name $SQLDatabaseName Running On Instance $SourceServerName & Store As A Var
    $DataSourceSQLObj = Get-DataSource -ProtectionGroup $ProtectionGroupSQLObj | Where-Object { $_.Name -eq $SQLDatabaseName -and $_.Instance -eq $SourceServerName} 

    write-host $ProtectionGroupSQLObj.name
    write-host $DataSourceSQLObj.name

	If ($DataSourceSQLObj -ne $null) #Only Continue If DB Exists
        { 
        #Add $DataSource As A SQLDataSource And Store As A Var
        $SQLDatabases = [Microsoft.Internal.EnterpriseStorage.Dls.UI.ObjectModel.SQL.SQLDataSource]$DataSourceSQLObj;
        #Get The Latest Disk Based (Express Full) Backup - Fails With Incremental Sync.
        $RecoveryPointsSQLObj = Get-Recoverypoint -DataSource $SQLDatabases | Where-Object { $_.HasFastRecoveryMarker -eq "Fast" -and $_.IsRecoverable -and $_.Location -eq "Disk"}  | Sort-Object BackupTime -Desc;
        
        If ($RecoveryPointsSQLObj.Count) #Check More Than 1 RP Is Returned
        { 
            $RecoveryPointToRestore = $RecoveryPointsSQLObj[0]; #Get The Latest RP (1st In List)
        } 
        Else #If Only 1 RP Is Returned
        { 
            $RecoveryPointToRestore = $RecoveryPointsSQLObj; 
        } 
        
        If ($RecoveryPointToRestore -eq $null) #If No RP's Are Returned...
        { 
            Write-EventLog -LogName $LoggingLogName -Source $LoggingSource -EventID $LoggingEventID -Message "Restore Failed. RP For DB: $SQLDatabaseName On: $SourceServerName Not Found In PG $ProtectionGroupSQLStr"
            Return 
        } 
                
        $length = $RecoveryPointToRestore.PhysicalPath.Length; #Return Number Of Files (i.e. LDF And MDF Files) - 2 = 1x LDF and 1x MDF 
        
        #Setup The Alternative DB Object Ready For Restore - Create The Objects & Add As Many FileLocationMapping Placeholders As There Are Files To $AlternativeDatabaseObj
        $AlternativeDatabaseObj = New-Object -TypeName Microsoft.Internal.EnterpriseStorage.Dls.UI.ObjectModel.SQL.AlternateDatabaseDetailsType; 
        $LocationMapping = New-Object Microsoft.Internal.EnterpriseStorage.Dls.UI.ObjectModel.SQL.FileLocationMapping[] $length; 
        $AlternativeDatabaseObj.LocationMapping = $LocationMapping 
        
        $i = 0; #Resets The Count (See While Loop Below)
        While($i -lt $length) #Perform The While Loop While $i Is Less Than The Number Of Files To Restore ($length). Add The Crrent File Names And Locations For Each File To Be Restored 
        {        
            $AlternativeDatabaseObj.LocationMapping[$i] = New-Object -TypeName Microsoft.Internal.EnterpriseStorage.Dls.UI.ObjectModel.SQL.FileLocationMapping; #Create The Object
            $AlternativeDatabaseObj.LocationMapping[$i].FileName = $RecoveryPointToRestore.FileSpecifications[$i].FileSpecification; #Set File Name For Files
            $AlternativeDatabaseObj.LocationMapping[$i].SourceLocation = [Microsoft.Internal.EnterpriseStorage.Dls.UI.ObjectModel.OMCommon.PathHelper]::GetParentDirectory($RecoveryPointToRestore.PhysicalPath[$i]); #Set Source Location (Path) For Files
            If ($AlternativeDatabaseObj.LocationMapping[$i].FileName.ToLower().EndsWith(".ldf")) #If LDF File Set Destination Location As $DestinationLDFPath
            { 
                $AlternativeDatabaseObj.LocationMapping[$i].DestinationLocation = $DestinationLDFPath 
            } 
            Else #If MDF File Set Destination Location As $DestinationMDFPath
            { 
                $AlternativeDatabaseObj.LocationMapping[$i].DestinationLocation = $DestinationMDFPath 
            }        
            $i++; #Increment Counter (Move Onto Next File)
        } 
        $AlternativeDatabaseObj.InstanceName = $DestinationServerName;  #Set Destination Server Name. If Restoring To Named Instance Include The Instance Name 
        $AlternativeDatabaseObj.DatabaseName = $DestinationDatabaseName; #Set Destination DB Name
        
        #Create A Recovery Option Variable Targetted To The Destination Server, Set To Rename The DB And Use The $AlternativeDatabaseObj Details Created Earlier
        $ROP = New-RecoveryOption -TargetServer $DestinationServerName -RecoveryLocation OriginalServerWithDBRename -SQL -RecoveryType Recover -AlternateDatabaseDetails $AlternativeDatabaseObj; 
            
        #Load SQL SMO Class - Required To Check If DB Exists On $DestinationServerName
        [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | Out-Null 
        #Create A New Object (SMO) Pass It The $DestinationServerName Variable And Store As A Var
        $SQLServerManagement = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server ($DestinationServerName)
        #If DB Exists At Destination, Write To Event Log
        If ($SQLServerManagement.databases[$DestinationDatabaseName] -ne $null)
        {
            Write-EventLog -LogName $LoggingLogName -Source $LoggingSource -EventID $LoggingEventID -Message "Error: DB $DestinationDatabaseName Already Exists On $DestinationServerName - Restore Will Fail"
        }
                    
        If ($PerformRestore) #Only Run Restore If $PerformRestore Is $true
        { 
            $RestoreJob = Recover-RecoverableItem -RecoverableItem $RecoveryPointToRestore -RecoveryOption $ROP; #Start The Restore Operation Using The $ROP Recovery Option Var
            #The While Loop Below Effectively Pauses The Script Until The Succeeded Or Failed If Clauses Are Encountered. 
            $Wait = 2; #Initial Wait Time
            While ($RestoreJob -ne $null -and $RestoreJob.HasCompleted -eq $false) 
            { 
                Start-Sleep -Seconds $Wait; 
                $Wait = 20; 
            } 
            
            If($RestoreJob.Status -ne "Succeeded") #If Job Fails Write Appropriately To Event Log
            { 
                Write-EventLog -LogName $LoggingLogName -Source $LoggingSource -EventID $LoggingEventID -Message "Restore Status: $($RestoreJob.Status)`n Start: $($RestoreJob.StartTime)`n  End: $($RestoreJob.EndTime)"
            } 
            Else #If Job Completes Write To Event Log
            { 
                Write-EventLog -LogName $LoggingLogName -Source $LoggingSource -EventID $LoggingEventID -Message "Restore Status: $($RestoreJob.Status)`n Start: $($RestoreJob.StartTime)`n  End: $($RestoreJob.EndTime)"
            } 
            
            $td = (New-Timespan -Start $RestoreJob.StartTime -end $RestoreJob.EndTime) #Calculate Time Taken To Restore & Write To Event Log
            Write-EventLog -LogName $LoggingLogName -Source $LoggingSource -EventID $LoggingEventID -Message "Elapsed time: Hours: $($td.Hours) Minutes:$($td.Minutes) Seconds:$($td.Seconds) MSecs:$($td.Milliseconds)"
        } 
        Else #If $PerformRestore Is Set To $false Write To Event Log
        { 
            Write-EventLog -LogName $LoggingLogName -Source $LoggingSource -EventID $LoggingEventID -Message "PerformRestore Varible Is $false - Restore Will Not Happen"
        } 
    } 
    Else #If DB Doesnt Exist As DataSource In DPM Protection Group Write Error To Event Log
    { 
        Write-EventLog -LogName $LoggingLogName -Source $LoggingSource -EventID $LoggingEventID -Message "Database $SQLDatabaseName On $SourceServerName Does Not Exist. Nothing To Restore!"
    } 
    Write-Host "*****Restore Complete*****"
}
    Disconnect-DPMServer $DPMServer #Disconnect DPM Server



