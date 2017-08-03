function Invoke-GetDPMServices {
$Services = @"
DPM
DPM Replication Agent
SQLAgent`$MSSQLSERVER
MSSQL`$MSSQLSERVER
Virtual Disk Service
Volume Shadow Copy
"@ -split "`r`n" | Get-Service -ComputerName inf-scdpm201601
}

function Get-DataSourceInfo {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$DataSourceID
    )
    process {
        Invoke-SQL -dataSource inf-scdpm201601 -database DPMDB_INF_SCDPM201601 -sqlCommand @"
exec dbo.prc_PRM_GetDataSourceInfo '$DataSourceID'
"@ -ConvertFromDataRow
    }
}


function Get-IMDataSource {
    Invoke-SQL -dataSource inf-scdpm201601 -database DPMDB_INF_SCDPM201601 -sqlCommand @"
SELECT *  FROM [DPMDB_INF_SCDPM201601].[dbo].[tbl_IM_DataSource]
"@ -ConvertFromDataRow
#tbl_PRM_DatasourceConfigInfo
}

function Get-ARMDataSource {
    Invoke-SQL -dataSource inf-scdpm201601 -database DPMDB_INF_SCDPM201601 -sqlCommand @"
SELECT *  FROM [DPMDB_INF_SCDPM201601].[dbo].[tbl_ARM_Datasource]
"@ -ConvertFromDataRow
#tbl_PRM_DatasourceConfigInfo
}



function Invoke-Test {
    #Get-DataSourceInfo -DataSourceID '4C907872-A6EB-499C-9E2E-F66894050EA4'

    $IMDataSources = Get-IMDataSource
    $ARMDataSources = Get-ARMDataSource
    $Results = $DataSources | Get-DataSourceInfo
}

function Remove-StuckJobs {
    param (
        $DPMServerName,
        $DPMDBName
    )
    Invoke-SQL -dataSource $DPMServerName -database $DPMDBName -sqlCommand @"
USE $DPMDBName

BEGIN TRAN

-- mark replica as invalid if there was some operation happening on that replica
UPDATE tbl_PRM_LogicalREplica
SET Validity = 1 -- Invalid
WHERE OwnerTaskIdLock IS NOT NULL AND
Validity <> 5 AND -- ProtectionStopped
Validity <> 6 -- Inactive

-- Release all the locks held
UPDATE tbl_PRM_LogicalREplica
SET OwnerTaskIdLock = null,
Status=8

if (select COUNT(name) from tbl_AM_Agent where Name like 'DPM RA v2%') > 0
begin
    exec sp_executesql N'UPDATE tbl_RM_ShadowCopy
    SET ArchivetaskId = NULL,
    RecoveryJobId = NULL'
end

UPDATE tbl_ARM_Datasource
SET Status = 0,
OwnerLockId = NULL
DELETE tbl_RM_DatasourceServerlock
DELETE tbl_RM_ShadowCopyLocks

-- Set All running tasks and jobs to failed
UPDATE tbl_TE_TaskTrail
SET ExecutionState = 3,
LastStateName = 'Failure',
StoppedDateTime = GetUtcDate()
WHERE ExecutionState NOT IN (2,3)

UPDATE tbl_JM_JobTrail
SET JobState= 'Failed',
EndDateTime = GetUtcDate()
WHERE jobstate= 'Execute' OR jobstate= 'Retire'

-- unreserve resources held
UPDATE tbl_MM_Global_Media
SET ReservationLevel = 0,
ReservationOwnerMMId = null

UPDATE tbl_MM_Global_Drive
SET ReservationLevel = 0,
ReservationOwnerMMId = null

UPDATE tbl_MM_Global_IEPortResource
SET ReservationLevel = 0,
ReservationOwnerMMId = null
COMMIT TRAN
"@ -ConvertFromDataRow
}

function Export-ProtectionGroups {
$Groups = Get-ProtectionGroup
$groups | Export-Clixml -Depth 3 -Path $home\protectiongroups.xml
$groups | ConvertTo-Json | Out-File -Encoding ascii -NoNewline -FilePath $home\ProtectionGroups.json
}

function Import-ProtectionGroups {
$groups = Import-Clixml -Path $home\protectiongroups.xml

}

function Get-DPMBinPath {
    param (
        $ComputerName
    )
    $DPMBinPathLocal = "C:\Program Files\Microsoft System Center 2016\DPM\DPM\bin"

    if ($ComputerName) {
        $DPMBinPathLocal | ConvertTo-RemotePath -ComputerName $ComputerName
    } else {
        $DPMBinPathLocal
    }
}

function Import-DataProtectionManagerModule {
    param (
        $ComputerName,
        $Prefix
    )
    $Session = New-PSSession -ComputerName $ComputerName
    Invoke-Command -Session $Session -ScriptBlock { ipmo -force DataProtectionManager }

    if ($Prefix) {
        Import-module (Import-PSSession -Session $Session -Module DataProtectionManager -DisableNameChecking -AllowClobber) -Global -Prefix $Prefix
    } else {
        Import-module (Import-PSSession -Session $Session -Module DataProtectionManager -DisableNameChecking -AllowClobber) -Global
    }
}

function New-TervisProtectionGroup {

}

function Compare-DPMProductionServers {
    param (
        $ComputerName,
        $OldComputerName,
        [Switch]$IncludeEqual
    )
    Import-DataProtectionManagerModule -ComputerName $OldComputerName -Prefix Old
    Import-DataProtectionManagerModule -ComputerName $ComputerName

    $AgentsOld = Get-OldProductionServer
    $Agents = Get-ProductionServer

    Compare-Object -ReferenceObject $AgentsOld -DifferenceObject $Agents -Property Name -IncludeEqual:$IncludeEqual
}

function Compare-DPMProtectionGroups {
    param (
        $ComputerName,
        $OldComputerName,
        [Switch]$IncludeEqual
    )
    Import-DataProtectionManagerModule -ComputerName $OldComputerName -Prefix Old
    Import-DataProtectionManagerModule -ComputerName $ComputerName

    $OldProtectionGroup = Get-OldProtectionGroup -DPMServerName $OldComputerName
    $ProtectionGroup = Get-ProtectionGroup -DPMServerName $ComputerName

    Compare-Object -ReferenceObject $OldProtectionGroup -DifferenceObject $ProtectionGroup -Property Name -IncludeEqual:$IncludeEqual
}

function Move-DPMAgents {
    param (
        $ComputerName,
        $OldComputerName
    )

    $AgentsToMove = Compare-DPMProductionServers -ComputerName $ComputerName -OldComputerName $ComputerName | 
    where SideIndicator -eq "<=" |
    where Name -NE $OldComputerName |
    Select -ExpandProperty Name

    Set-DPMServernameOnRemoteComputer -Computername $AgentsToMove -DPMServerName $ComputerName

    foreach ($Agent in $AgentsToMove) {
        Invoke-AttachDPMProductionServer -DPMServerName $ComputerName -Name $Agent        
    }

    $ProtectionGroupNamesToCreate = Compare-DPMProtectionGroups -ComputerName $ComputerName -OldComputerName $OldComputerName |
    where SideIndicator -eq "<=" |
    Select -ExpandProperty Name

    Import-DataProtectionManagerModule -ComputerName $OldComputerName -Prefix Old
    Import-DataProtectionManagerModule -ComputerName $ComputerName

    $OldProtectionGroup = Get-OldProtectionGroup -DPMServerName $OldComputerName

    $ProtectionGroupsToCreate = $OldProtectionGroup | where Name -In $ProtectionGroupNamesToCreate
    Set-ProtectionGroup -ProtectionGroup $ProtectionGroupsToCreate[0]
    
    $pgroup = $ProtectionGroupsToCreate[0]
    $pgroup.DPMServerName = "inf-scdpm201602.tervis.prv"
    Set-ProtectionGroup -ProtectionGroup $pgroup

    $NewPGroup = New-ProtectionGroup -DPMServerName $ComputerName -Name Stores-OrangeBeach

    $ProtectionGroup = New-ProtectionGroup -DPMServerName $ComputerName -Name Stores-OrangeBeach

    Add-DPMChildDatasource
    Set-DPMProtectionType
    Set-DPMDatasourceDefaultDiskAllocation
    Set-DPMDatasourceDiskAllocation

    
}

function Get-DPMStoreDatabaSourcesNotProtected {
    $DataSources = Get-DPMDatasource
    
    $DataSources | 
    where ObjectType -Match SQL |
    where CurrentProtectionState -NE Protected |
    where Name -NotIn "master","tempdb","model","msdb" |
    where {$_.Computer -match "^[0-9]"} |
    where SqlScratchSpace -NotMatch UPS
}

function Remove-ProductionServer {
    param (
        [Parameter(Mandatory)]$ComputerName,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$Name
    )
    begin {
        $DPMServer = Connect-DPMServer $ComputerName
    }
    process {
        if ($DPMServer) {
            $DPMServer.RemoveProductionServer($Name)
        }
    }
    end {
        $DPMServer.Dispose()
    }
}

function Invoke-AttachDPMProductionServer {
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]$Name,
        [parameter(Mandatory)]$DPMServerName,
        $Credential = (Get-PasswordstateCredential -PasswordID 4037)
    )
    $AttachProductionServerScriptPath = "C:\Program Files\Microsoft System Center 2016\DPM\DPM\bin\Attach-ProductionServer.ps1"
    
    $Command = "& `"$AttachProductionServerScriptPath`" -DPMServerName $DPMServerName -PSName $Name -UserName $(($Credential.Username -split("\\"))[1]) -Password $($Credential.GetNetworkCredential().Password) -Domain tervis.prv"
    Invoke-PsExec -ComputerName $DPMServerName -Command $Command -IsPSCommand -IsLongPSCommand -CustomPsExecParameters "-s"
}

function Set-DPMServernameOnRemoteComputer {
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]$Computername,
        [parameter(Mandatory)]$DPMServerName
    )
    Invoke-PsExec -ComputerName $Computername -CustomPsExecParameters "-s" -Command "`"C:\Program Files\Microsoft Data Protection Manager\DPM\bin\SetDpmServer.exe`" -DPMServerName $DPMServerName"
}

function Invoke-DPMConfigureSharePoint {
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]$Computername,
        [Switch]$EnableSharePointProtection,
        [Switch]$EnableSPSearchProtection,
        [Switch]$ResolveAllSQLAliases,
        $TempPath
    )
    $Command = "`"C:\Program Files\Microsoft Data Protection Manager\DPM\bin\ConfigureSharePoint.exe`""
    Invoke-PsExec -ComputerName $Computername -CustomPsExecParameters "-s" -Command $Command
}

New-Alias -Name Get-DPMAgentDataSource -Value Get-DPMProductionServerDataSource
New-Alias -Name Get-AgentDataSource -Value Get-DPMProductionServerDataSource
New-Alias -Name Get-ProductionServerDataSource -Value Get-DPMProductionServerDataSource

function Get-DPMProductionServerDataSource {
    param (
        $Name,
        $ComputerName,
        [Switch]$Inquire
    )

    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        $ProductionServer = Get-ProductionServer | 
        where Name -EQ $Using:Name

        if (-not $ProductionServer) {
            Throw "No production server with name $Using:Name was found"
        }

        Get-Datasource -ProductionServer $ProductionServer -Inquire:$Using:Inquire
    }
}

function Move-TervisStoreDatabaseToNewDPMServer {
    param(
        [parameter(Mandatory)]$Computername,
        [parameter(Mandatory)]$OldDPMServer
    )

    $StoreNodeDefinition = Get-DPMStoreProtectionGroupDefinition -Name $ComputerName
    $StoreInformation = Get-TervisStoreDatabaseInformation -Computername $($StoreNodeDefinition.Name)
    $StoreName = $StoreInformation.StoreName
    $DataSourceName = $StoreInformation.DatabaseName
    $ProtectionGroupName = "Stores-$StoreName" -replace " ","_"
    
    Remove-DPMDataSourceFromProtectionGroup -Computername $Computername -DatasourceName $DataSourceName -DPMServerName $OldDPMServer
    Set-DPMServernameOnRemoteComputer -Computername $StoreNodeDefinition.Name -DPMServerName $StoreNodeDefinition.DPMServerName
    Invoke-AttachDPMProductionServer -Name $StoreNodeDefinition.Name -DPMServerName $StoreNodeDefinition.DPMServerName
    Invoke-ProtectDPMDataSource -DPMServerName $StoreNodeDefinition.DPMServerName `
        -ProductionServerName $Computername `
        -DatasourceName $DataSourceName `
        -ProtectionGroupName $ProtectionGroupName `
        -DPMProtectionGroupSchedulePolicy $StoreNodeDefinition.ProtectionGroupSchedule `
        -EnableCompression
            
#    Connect-DPMServer -DPMServerName $StoreNodeDefinition.DPMServerName
#    Set-DPMServernameOnRemoteComputer -Computername $StoreNodeDefinition.Name -DPMServerName $StoreNodeDefinition.DPMServerName
#    Invoke-AttachDPMProductionServer -Name $StoreNodeDefinition.Name -DPMServerName $StoreNodeDefinition.DPMServerName
#    $ProductionServer = Get-ProductionServer | where servername -eq $($StoreNodeDefinition.Name)
#    $Datasource = Get-Datasource -ProductionServer $ProductionServer -Inquire | where { ($_.logicalpath,$_.name) -contains $DatasourceName }
#    $ProtectionGroup = New-ProtectionGroup -Name $ProtectionGroupName
#    Add-childDatasource -ProtectionGroup $ProtectionGroup -ChildDatasource $Datasource
#    Set-ProtectionType -ProtectionGroup $ProtectionGroup -ShortTerm disk
#    Set-TervisDPMProtectionGroupSchedule -ProtectionGroup $ProtectionGroup -DPMProtectionGroupSchedulePolicy $StoreNodeDefinition.ProtectionGroupSchedule
#    Get-DatasourceDiskAllocation -Datasource $Datasource
#    Set-DatasourceDiskAllocation -Datasource $Datasource -ProtectionGroup $ProtectionGroup
#    Set-ReplicaCreationMethod -ProtectionGroup $ProtectionGroup -NOW
#    Set-DPMPerformanceOptimization -ProtectionGroup $ProtectionGroup -EnableCompression
#    Set-protectiongroup $ProtectionGroup
#    Disconnect-DPMServer -DPMServerName $StoreNodeDefinition.DPMServerName
}

function Invoke-ProtectDPMDataSource {
   param(
        [Parameter(Mandatory)]$DPMServerName,
        [Parameter(Mandatory)]$ProductionServerName,
        [Parameter(Mandatory)]$DatasourceName,
        $ChildDatasourceName,
        [Parameter(Mandatory)]$ProtectionGroupName,
        [Parameter(Mandatory)]$DPMProtectionGroupSchedulePolicy,
        [switch]$EnableCompression
    )
    Connect-DPMServer -DPMServerName $StoreNodeDefinition.DPMServerName
    if( -not ($ProtectionGroup = (Get-ProtectionGroup | where name -eq $ProtectionGroupName))){
        $ProtectionGroup = New-ProtectionGroup -Name $ProtectionGroupName
    }
    $ProductionServer = Get-ProductionServer | where servername -eq $($StoreNodeDefinition.Name)
    $Datasource = Get-Datasource -ProductionServer $ProductionServer -Inquire | where { ($_.logicalpath,$_.name) -contains $DatasourceName }
    if($ChildDatasourceName){
        $ChildDatasource = Get-ChildDatasource -ChildDatasource $Datasource | where Name eq $ChildDatasourceName
        Add-childDatasource -ProtectionGroup $ProtectionGroup -ChildDatasource $ChildDatasource
    }
    else {
        Add-childDatasource -ProtectionGroup $ProtectionGroup -ChildDatasource $Datasource
    }
    Set-ProtectionType -ProtectionGroup $ProtectionGroup -ShortTerm disk
    Set-TervisDPMProtectionGroupSchedule -ProtectionGroup $ProtectionGroup -DPMProtectionGroupSchedulePolicy $DPMProtectionGroupSchedulePolicy
    if ($Datasource.ObjectType -eq "Volume"){
        Get-DatasourceDiskAllocation -Datasource $Datasource -CalculateSize
    }
    else {
        Get-DatasourceDiskAllocation -Datasource $Datasource
    }
    Set-DatasourceDiskAllocation -Datasource $Datasource -ProtectionGroup $ProtectionGroup
    Set-ReplicaCreationMethod -ProtectionGroup $ProtectionGroup -NOW
    if ($EnableCompression){
        Set-DPMPerformanceOptimization -ProtectionGroup $ProtectionGroup -EnableCompression
    }
    Set-protectiongroup $ProtectionGroup
    Disconnect-DPMServer -DPMServerName $StoreNodeDefinition.DPMServerName
}

function New-TervisDPMProtectionGroup
{
    ####https://blogs.technet.microsoft.com/dpm/2008/03/18/cli-script-create-protection-groups-for-disk-based-backups/####
    param(
        [Parameter(Mandatory)]$DPMServerName,
        [Parameter(Mandatory)]$ProductionServerName,
        [Parameter(Mandatory)]$DatasourceName,
        $ChildDatasourceName,
        [Parameter(Mandatory)]$ProtectionGroupName,
        [Parameter(Mandatory)]$DPMProtectionGroupSchedulePolicy
    )

        $DPMProtectionGroupPolicyToApply = Get-DPMProtectionGroupSchedulePolicyDefinition -DPMProtectiongroupSchedulePolicy $DPMProtectionGroupSchedulePolicy
        $ProductionServer = Get-ProductionServer | where { ($_.machinename,$_.name) -contains $ProductionServerName }
        $Datasource = Get-Datasource -ProductionServer $ProductionServer -Inquire | where { ($_.logicalpath,$_.name) -contains $DatasourceName }
        $ChildDatasource = Get-ChildDatasource -ChildDatasource $Datasource -Inquire | where { ($_.logicalpath,$_.name) -contains $ChildDatasourceName }
        $ProtectionGroup = New-ProtectionGroup -DPMServerName $DPMServerName -Name $ProtectionGroupName
        Add-childDatasource -ProtectionGroup $ProtectionGroup -ChildDatasource $ChildDatasource
        Set-ProtectionType -ProtectionGroup $ProtectionGroup -ShortTerm disk
        Set-TervisDPMProtectionGroupSchedule -DPMServerName $DPMServerName -ProtectionGroup $ProtectionGroup -DPMProtectionGroupSchedulePolicy $DPMProtectionGroupSchedulePolicy
#        Set-PolicyObjective -ProtectionGroup $ProtectionGroup -RetentionRangeInDays 21 -SynchronizationFrequency 15
#        $PolicySchedule = Get-PolicySchedule -ProtectionGroup $ProtectionGroup -ShortTerm| where { $_.JobType -eq “ShadowCopy” }
#        Set-PolicySchedule -ProtectionGroup $ProtectionGroup -Schedule $PolicySchedule -DaysOfWeek su,mo,tu,we,th,fr,sa -TimesOfDay 8:00,16:00,00:00
        Get-DatasourceDiskAllocation -Datasource $Datasource -Calculatesize
        Set-DatasourceDiskAllocation -Datasource $Datasource -ProtectionGroup $ProtectionGroup
        Set-ReplicaCreationMethod -ProtectionGroup $ProtectionGroup -NOW
        Set-protectiongroup $ProtectionGroup
}
 
function Set-TervisDPMProtectionGroupSchedule
{
    ####https://blogs.technet.microsoft.com/dpm/2008/03/18/cli-script-create-protection-groups-for-disk-based-backups/####
    param(
        [Parameter(Mandatory)]$ProtectionGroup,
        [Parameter(Mandatory)]$DPMProtectionGroupSchedulePolicy
    )
        $PolicyScheduletoSet = Get-DPMProtectionGroupSchedulePolicyDefinition -DPMProtectiongroupSchedulePolicy $DPMProtectionGroupSchedulePolicy
        Set-PolicyObjective -ProtectionGroup $ProtectionGroup -RetentionRangeInDays $PolicyScheduletoSet.RetentionRangeInDays -SynchronizationFrequency $PolicyScheduletoSet.SynchronizationFrequencyinMinutes
        $PolicySchedule = (Get-PolicySchedule -ProtectionGroup $ProtectionGroup -ShortTerm)[1] #| where { $_.JobType -eq “ShadowCopy” }
        Set-PolicySchedule -ProtectionGroup $ProtectionGroup -Schedule $PolicySchedule -DaysOfWeek $($PolicyScheduletoSet.DaysOfWeek) -TimesOfDay $PolicyScheduletoSet.TimesofDay
}

function New-PSCustomObjectDefinition {
    param (
        [parameter(Mandatory)]$IndexObjects,
        [parameter(Mandatory)]$FieldList
    )
    Foreach ($IndexObject in $IndexObjects)  {
@"
        [PSCustomObject][Ordered] @{
            Name = "$IndexObject"
            TimeZoneSchedule = ""
            OffsetinMinutes = 
            DPMServerName = "inf-scdpmsql01.tervis.prv"
        },
"@
    }
}

function Get-DPMProtectionGroupSchedulePolicyDefinition{
    param(
        [String]$DPMProtectiongroupSchedulePolicy
    )
    if($DPMProtectiongroupSchedulePolicy){
        $DPMProtectionGroupSchedulePolicies| Where name -EQ $DPMProtectiongroupSchedulePolicy
    }
    else{$DPMProtectionGroupSchedulePolicies}
}

function Get-DPMStoreProtectionGroupDefinition{
    param(
        [String]$Name
    )
    if($Name){
        $DPMStoreProtectionGroupDefinitions | Where name -EQ $Name
    }
    else{$DPMStoreProtectionGroupDefinitions}
}

function Remove-DPMDataSourceFromProtectionGroup {
    param(
        [parameter(Mandatory)]$Computername,
        [parameter(Mandatory)]$DatasourceName,
        $DPMServerName
    )
    if($DPMServerName){
        Connect-DPMServer -DPMServerName $DPMServerName
    }
    $ProtectionGroup = Get-ProtectionGroupofDataSource -ProductionServer $Computername -DataSourceName $datasourcename -Modifiable
    $datasource = Get-DPMDatasource -ProtectionGroup $ProtectionGroup | where name -eq $DataSourceName
    Remove-DPMChildDatasource -ProtectionGroup $ProtectionGroup -ChildDatasource $Datasource -KeepDiskData
    Set-protectiongroup $ProtectionGroup
    if($DPMServerName){
        Disconnect-DPMServer -DPMServerName $DPMServerName
    }
}

$DPMProtectionGroupSchedulePolicies = [PSCustomObject][Ordered] @{
        Name = "Stores-21Day-60Min-10pm"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "15"
        TimesofDay = "22:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
    },
    [PSCustomObject][Ordered] @{
        Name = "Stores-21day-120Min-12pm"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "120"
        TimesofDay = "00:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
    },
    [PSCustomObject][Ordered] @{
        Name = "21day-30Min-7am_3pm_11pm"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "30"
        TimesofDay = "07:00,15:00,23:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
    }

function Get-ProtectionGroupofDataSource {
    param (
        [parameter(Mandatory)]$ProductionServerName,
        [parameter(Mandatory)]$DataSourceNameName,
        [switch]$Modifiable
    )

    if ($Modifiable){
        Get-DPMDatasource | where {$_.Computer -eq $ProductionServerName -and $_.Name -eq $DataSourceNameName} | select ProtectionGroup -ExpandProperty ProtectionGroup | Get-ModifiableProtectionGroup
    }
    else{
        Get-DPMDatasource | where {$_.Computer -eq $ProductionServerName -and $_.Name -eq $DataSourceName} | select ProtectionGroup -ExpandProperty ProtectionGroup
    }

}

$DPMStoreProtectionGroupDefinitions = [PSCustomObject][Ordered] @{
        Name = "1010OSBO3-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "1050PCBO-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3014SABO1-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3002CHBO-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "1060KWBO-PC2"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3029PFBO-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3041ORBO-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3007FMBO4-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "2010MBBO3-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3015MABO-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3026ANBO3-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3001GBBO2-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "1040FMBO-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "1030VGBO1-PC"
        ProtectionGroupSchedule= "Stores-21Day-60Min-10pm"
        OffsetinMinutes = "5"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3045COBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3036VBBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3020SDBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3048INBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3034DNBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "HAMBO-VM"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3047TPBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3049SPBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3028AVBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3038WBBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3039SEBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3046CNBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3042NOBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3004CGBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3024NSBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3022MMBO-PC2"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3044FWBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3008OBBO2-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3043BOBO1-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3023MYBO1-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3033NPBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3035SABO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3050KCBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3040SABO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3025AUBO3-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3032NHBO-PCNEW"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3030JVBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "1010OSMGR02-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3052ABO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3016BRBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3005SVBO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3018LABO-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "1010OSBO2-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "3003BRBO2-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "1020PBBO2-PC"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "INF-DONTESTBO"
        ProtectionGroupSchedule= "Stores-21day-120Min-12pm"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    }
 

#Export-ModuleMember -Function * -Alias * 
#Export-ModuleMember -Function * -Alias *

