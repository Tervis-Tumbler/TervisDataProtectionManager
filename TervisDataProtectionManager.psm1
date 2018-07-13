$ModulePath = (Get-Module -ListAvailable TervisDataProtectionManager).ModuleBase
. $ModulePath\DPMProtectionGroupDefinitions.ps1
. $ModulePath\DPMProtectionGroupSchedulePolicyDefinitions.ps1

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
        $Credential = (Get-PasswordstatePassword -AsCredential -ID 4037)
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

    $ProductionServerDefinition = Get-DPMProductionServerDefinition -Name $ComputerName
    $StoreInformation = Get-TervisStoreDatabaseInformation -Computername $($ProductionServerDefinition.Name)
    $StoreName = $StoreInformation.StoreName
    $DataSourceName = $StoreInformation.DatabaseName
    $ProtectionGroupName = "Stores-$StoreName" -replace " ","_"
    
    Remove-DPMDataSourceFromProtectionGroup -Computername $Computername -DatasourceName $DataSourceName -DPMServerName $OldDPMServer
    Set-DPMServernameOnRemoteComputer -Computername $ProductionServerDefinition.Name -DPMServerName $ProductionServerDefinition.DPMServerName
    Invoke-AttachDPMProductionServer -Name $ProductionServerDefinition.Name -DPMServerName $ProductionServerDefinition.DPMServerName
    Invoke-ProtectDPMDataSource -DPMServerName $ProductionServerDefinition.DPMServerName `
        -ProductionServerName $Computername `
        -DatasourceName $DataSourceName `
        -ProtectionGroupName $ProtectionGroupName `
        -DPMProtectionGroupSchedulePolicy $ProductionServerDefinition.ProtectionGroupSchedule `
        -EnableCompression
            
#    Connect-DPMServer -DPMServerName $ProductionServerDefinition.DPMServerName
#    Set-DPMServernameOnRemoteComputer -Computername $ProductionServerDefinition.Name -DPMServerName $ProductionServerDefinition.DPMServerName
#    Invoke-AttachDPMProductionServer -Name $ProductionServerDefinition.Name -DPMServerName $ProductionServerDefinition.DPMServerName
#    $ProductionServer = Get-ProductionServer | where servername -eq $($ProductionServerDefinition.Name)
#    $Datasource = Get-Datasource -ProductionServer $ProductionServer -Inquire | where { ($_.logicalpath,$_.name) -contains $DatasourceName }
#    $ProtectionGroup = New-ProtectionGroup -Name $ProtectionGroupName
#    Add-childDatasource -ProtectionGroup $ProtectionGroup -ChildDatasource $Datasource
#    Set-ProtectionType -ProtectionGroup $ProtectionGroup -ShortTerm disk
#    Set-TervisDPMProtectionGroupSchedule -ProtectionGroup $ProtectionGroup -DPMProtectionGroupSchedulePolicy $ProductionServerDefinition.ProtectionGroupSchedule
#    Get-DatasourceDiskAllocation -Datasource $Datasource
#    Set-DatasourceDiskAllocation -Datasource $Datasource -ProtectionGroup $ProtectionGroup
#    Set-ReplicaCreationMethod -ProtectionGroup $ProtectionGroup -NOW
#    Set-DPMPerformanceOptimization -ProtectionGroup $ProtectionGroup -EnableCompression
#    Set-protectiongroup $ProtectionGroup
#    Disconnect-DPMServer -DPMServerName $ProductionServerDefinition.DPMServerName
}

function Set-TervisDPMProtectionType {
    param(
        [Parameter(Mandatory)]$ModifiableProtectiongroup,
        [switch]$Online
    )
    if ($Online) {
        Set-DPMProtectionType -ProtectionGroup $ModifiableProtectiongroup -ShortTerm Disk -LongTerm Online
    }
    else {
        Set-ProtectionType -ProtectionGroup $ModifiableProtectiongroup -ShortTerm disk
    }
}

function Add-DPMDatasourcetoProtectionGroup {
   param(
        [Parameter(Mandatory)]$Datasource,
        [Parameter(Mandatory)]$ModifiableProtectionGroup,
        [switch]$Online
    )

#    if (-not ($Datasource.Protectiongroup)){
    if (-not $Datasource.Protected){
        Add-childDatasource -ProtectionGroup $ModifiableProtectionGroup -ChildDatasource $Datasource
    }
    else{
        Add-childDatasource -ProtectionGroup $ModifiableProtectionGroup -ChildDatasource $Datasource -Online
    }
}

function Invoke-ProtectDPMDataSource {
    [CmdletBinding()]
    param(
#        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$DPMServerName,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ProductionServerName,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName,ParameterSetName="DataSourceName")]$DatasourceName,
        [Parameter(ValueFromPipelineByPropertyName,ParameterSetName="ChildDatasourceNames")]$ChildDatasourceNames,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ProtectionGroupName,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$DPMProtectionGroupSchedulePolicyName,
        [Parameter(ValueFromPipelineByPropertyName)]$DataSourceType,
        [Parameter(ValueFromPipelineByPropertyName)][switch]$EnableCompression,
        [Parameter(ValueFromPipelineByPropertyName)][switch]$Online
    )
#    Connect-DPMServer -DPMServerName $DPMServerName
    if( -not ($ProtectionGroup = (Get-ProtectionGroup | where name -eq $ProtectionGroupName))){
        $ModifiableProtectionGroup = New-ProtectionGroup -Name $ProtectionGroupName
    }
    else { 
        $ProtectionGroup = Get-ProtectionGroup | where name -eq $ProtectionGroupName
        $ModifiableProtectionGroup = Get-ModifiableProtectionGroup -ProtectionGroup $ProtectionGroup
    }
    $ProductionServer = Get-ProductionServer | where servername -eq $ProductionServerName
#    $Datasource = Get-Datasource -ProductionServer $ProductionServer -Inquire | where { ($_.logicalpath,$_.name) -contains $DatasourceName }
    $Datasources = Get-Datasource -ProductionServer $ProductionServer -Inquire     
    if($ChildDatasourceNames){
        foreach ($CDSName in $ChildDatasourceNames){
            $DatasourceName = Split-Path $CDSName -Parent
            $ChildDatasourceName = Split-Path $CDSName -Leaf
            $Datasource = $Datasources | where { ($_.logicalpath,$_.name) -contains $DatasourceName } 
            $ChildDatasource = Get-ChildDatasource -ChildDatasource $Datasource -Inquire| where Name -EQ $ChildDatasourceName
            if (-not($ChildDatasource.CurrentlyProtected)){
                Add-ChildDatasource -ChildDatasource $ChildDatasource -ProtectionGroup $ModifiableProtectionGroup
            }
        }
    }
    elseif($DatasourceType -eq "SQL"){
        $Datasource = $Datasources | where {(($_.logicalpath,$_.name) -contains $DatasourceName) -and ($_.ObjectType -match "SQL") }
        if (-not($Datasource.CurrentlyProtected)){
            Add-ChildDatasource -ChildDatasource $Datasource -ProtectionGroup $ModifiableProtectionGroup
        }
    }
    else{
        $Datasource = $Datasources | where {($_.logicalpath,$_.name) -contains $DatasourceName}
        if (-not($Datasource.CurrentlyProtected)){
            Add-ChildDatasource -ChildDatasource $Datasource -ProtectionGroup $ModifiableProtectionGroup
        }

    }

    $SplatVariable = New-SplatVariable -Function Set-TervisDPMProtectionType -Variables (Get-Variable)
    Set-TervisDPMProtectionType @SplatVariable

    if($Online){
#        $SplatVariable = New-SplatVariable -Function Add-DPMDatasourcetoProtectionGroup -Variables (Get-Variable)
#        Add-DPMDatasourcetoProtectionGroup @SplatVariable
        Add-ChildDatasource -ProtectionGroup $ModifiableProtectionGroup -ChildDatasource $Datasource -Online
    }

    $SplatVariable = New-SplatVariable -Function Set-TervisDPMProtectionGroupSchedule -Variables (Get-Variable)
    Set-TervisDPMProtectionGroupSchedule @SplatVariable

#    if ($ChildDatasourceNames){
#        Get-DatasourceDiskAllocation -Datasource $Datasource -CalculateSize
#    }
#    else {
#        Get-DatasourceDiskAllocation -Datasource $Datasource
#    }
    Get-DatasourceDiskAllocation -Datasource $Datasource
    if (-not ($Datasource.Protectiongroup)){
        Set-DatasourceDiskAllocation -Datasource $Datasource -ProtectionGroup $ModifiableProtectionGroup
    }

    Set-ReplicaCreationMethod -ProtectionGroup $ModifiableProtectionGroup -NOW
    if ($EnableCompression){
        Set-DPMPerformanceOptimization -ProtectionGroup $ModifiableProtectionGroup -EnableCompression
    }
    Set-protectiongroup $ModifiableProtectionGroup
#    Disconnect-DPMServer -DPMServerName $DPMServerName
}

function New-TervisDPMProtectionGroup {
    ####https://blogs.technet.microsoft.com/dpm/2008/03/18/cli-script-create-protection-groups-for-disk-based-backups/####
    param(
        [Parameter(Mandatory)]$DPMServerName,
        [Parameter(Mandatory)]$ProductionServerName,
        [Parameter(Mandatory)]$DatasourceName,
        $ChildDatasourceName,
        [Parameter(Mandatory)]$ProtectionGroupName,
        [Parameter(Mandatory)]$DPMProtectionGroupSchedulePolicyName
    )

        $DPMProtectionGroupPolicyToApply = Get-DPMProtectionGroupSchedulePolicyDefinition -DPMProtectiongroupSchedulePolicy $DPMProtectionGroupSchedulePolicyName
        $ProductionServer = Get-ProductionServer | where { ($_.machinename,$_.name) -contains $ProductionServerName }
        $Datasource = Get-Datasource -ProductionServer $ProductionServer -Inquire | where { ($_.logicalpath,$_.name) -contains $DatasourceName }
        $ChildDatasource = Get-ChildDatasource -ChildDatasource $Datasource -Inquire | where { ($_.logicalpath,$_.name) -contains $ChildDatasourceName }
        $ProtectionGroup = New-ProtectionGroup -DPMServerName $DPMServerName -Name $ProtectionGroupName
        Add-childDatasource -ProtectionGroup $ProtectionGroup -ChildDatasource $ChildDatasource
        Set-ProtectionType -ProtectionGroup $ProtectionGroup -ShortTerm disk
        Set-TervisDPMProtectionGroupSchedule -DPMServerName $DPMServerName -ProtectionGroup $ProtectionGroup -DPMProtectionGroupSchedulePolicy $DPMProtectionGroupSchedulePolicyName
#        Set-PolicyObjective -ProtectionGroup $ProtectionGroup -RetentionRangeInDays 21 -SynchronizationFrequency 15
#        $PolicySchedule = Get-PolicySchedule -ProtectionGroup $ProtectionGroup -ShortTerm| where { $_.JobType -eq “ShadowCopy” }
#        Set-PolicySchedule -ProtectionGroup $ProtectionGroup -Schedule $PolicySchedule -DaysOfWeek su,mo,tu,we,th,fr,sa -TimesOfDay 8:00,16:00,00:00
        Get-DatasourceDiskAllocation -Datasource $Datasource -Calculatesize
        Set-DatasourceDiskAllocation -Datasource $Datasource -ProtectionGroup $ProtectionGroup
        Set-ReplicaCreationMethod -ProtectionGroup $ProtectionGroup -NOW
        Set-protectiongroup $ProtectionGroup
}

function Invoke-ConfigureDPMProtectionGroupOnlineProtection {
    param(
        [Parameter(Mandatory)]$DPMServerName,
        [Parameter(Mandatory)]$ProtectionGroupName,
        [Parameter(Mandatory)]$DPMProtectionGroupSchedulePolicyName
    )
    Connect-DPMServer $DPMServerName
    $DataSourceList = Get-Datasource
    $ProtectionGroup = Get-ProtectionGroup | where name -EQ $ProtectionGroupName
    $ModifiableProtectionGroup = Get-ModifiableProtectionGroup -ProtectionGroup $ProtectionGroup
    $PGDatasources = $DataSourceList | where protectiongroupname -eq $ProtectionGroupName


#    $ProductionServerDefinition = Get-DPMProductionServerDefinition -Name $Childdatasource.Computer
#    $DPMProtectionGroupSchedulePolicyName = $ProductionServerDefinition.ProtectionGroupSchedule

#    $SplatVariable = New-SplatVariable -Function Set-TervisDPMProtectionType -Variables (Get-Variable)
#    Set-TervisDPMProtectionType @SplatVariable
    
    Set-DPMProtectionType -ProtectionGroup $ModifiableProtectiongroup -ShortTerm Disk -LongTerm Online
    

    foreach ($Datasource in $PGDatasources){
        #$Childdatasource = $DataSource
        $SplatVariable = New-SplatVariable -Function Add-DPMDatasourcetoProtectionGroup -Variables (Get-Variable)
        Add-DPMDatasourcetoProtectionGroup @SplatVariable -Online
    }

    $SplatVariable = New-SplatVariable -Function Set-TervisDPMProtectionGroupSchedule -Variables (Get-Variable)
    
    Set-protectiongroup $ModifiableProtectionGroup
    Disconnect-DPMServer
}    

function Set-TervisDPMProtectionGroupSchedule {
    ####https://blogs.technet.microsoft.com/dpm/2008/03/18/cli-script-create-protection-groups-for-disk-based-backups/####
    param(
        [Parameter(Mandatory)]$ModifiableProtectionGroup,
        [Parameter(Mandatory)]$DPMProtectionGroupSchedulePolicyName,
        $ProductionServerTimeZoneOffset = "0",
        [switch]$Online
    )
    $PolicyScheduletoSet = Get-DPMProtectionGroupSchedulePolicyDefinition -DPMProtectiongroupSchedulePolicy $DPMProtectionGroupSchedulePolicyName
    $PolicyScheduleTimesofDay = @()
    foreach ($TimeofDay in $PolicyScheduletoSet.TimesofDay){
        $PolicyScheduleTimesofDay += get-date (Get-Date $TimeofDay).AddMinutes($ProductionServerTimeZoneOffset) -UFormat %R
    }

    if ($PolicyScheduletoSet.SynchronizationFrequencyinMinutes -eq 0){
        Set-PolicyObjective -ProtectionGroup $ModifiableProtectionGroup -RetentionRangeInDays $PolicyScheduletoSet.RetentionRangeInDays -BeforeRecoveryPoint
    }
    else {
        Set-PolicyObjective -ProtectionGroup $ModifiableProtectionGroup -RetentionRangeInDays $PolicyScheduletoSet.RetentionRangeInDays -SynchronizationFrequency $PolicyScheduletoSet.SynchronizationFrequencyinMinutes
    }
    if($ShadowCopyPolicySchedule = Get-PolicySchedule -ProtectionGroup $ModifiableProtectionGroup -ShortTerm | where { $_.JobType -eq “ShadowCopy” }){
        Set-PolicySchedule -ProtectionGroup $ModifiableProtectionGroup -Schedule $ShadowCopyPolicySchedule -DaysOfWeek $($PolicyScheduletoSet.DaysOfWeek) -TimesOfDay $PolicyScheduleTimesofDay
    }
    if($FullReplicationforApplicationPolicySchedule = Get-PolicySchedule -ProtectionGroup $ModifiableProtectionGroup -ShortTerm | where { $_.JobType-eq “FullReplicationForApplication” }){
        Set-PolicySchedule -ProtectionGroup $ModifiableProtectionGroup -Schedule $FullReplicationforApplicationPolicySchedule -DaysOfWeek $($PolicyScheduletoSet.DaysOfWeek) -TimesOfDay $PolicyScheduleTimesofDay
    }
    
    if ($Online) {
        $OnlineRetentionRange = (New-Object -TypeName Microsoft.Internal.EnterpriseStorage.Dls.UI.ObjectModel.OMCommon.RetentionRange -ArgumentList $([int]$PolicyScheduletoSet.OnlineRetentionRangeInDays), Days)
        Set-PolicyObjective -ProtectionGroup $ModifiableProtectionGroup -OnlineRetentionRangeList $OnlineRetentionRange
        $OnlineSchedule = Get-DPMPolicySchedule -ProtectionGroup $ModifiableProtectionGroup -LongTerm Online
        Set-Policyschedule -ProtectionGroup $ModifiableProtectionGroup -Schedule $OnlineSchedule[0] -TimesOfDay $PolicyScheduletoSet.OnlineTOD
    }
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
        [String]$DPMProtectionGroupSchedulePolicyName
    )
    if($DPMProtectionGroupSchedulePolicyName){
        $DPMProtectionGroupSchedulePolicies| Where name -EQ $DPMProtectionGroupSchedulePolicyName
    }
    else{$DPMProtectionGroupSchedulePolicies}
}

function Get-DPMProductionServerDefinition{
    param(
        [String]$Name
    )
    if($Name){
        $ProductionServerDefinitions | Where name -EQ $Name
    }
    else{$ProductionServerDefinitions}
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

function Invoke-CreateNewDPMServerRecoveryPoints {
   param(
        [Parameter(Mandatory)]$DPMServerName,
        $ProtectiongroupName,
        [Parameter(Mandatory)][ValidateSet(“ExpressFull”,”Online”)]$BackupType
    )
    Connect-DPMServer -DPMServerName $DPMServerName
    if ($ProtectiongroupName) {
        $ProtectionGroups = Get-ProtectionGroup | where name -eq $ProtectiongroupName
    }
    else {
        $ProtectionGroups = Get-ProtectionGroup
    }
    $DataSourceList = Get-Datasource
    foreach ($Protectiongroup in $ProtectionGroups) {
        $PGDataSources = $DataSourceList | where protectiongroupname -eq $ProtectionGroup.Name
        if ($BackupType -eq "ExpressFull"){
            foreach ($PGDataSource in $PGDataSources){
                New-DPMRecoveryPoint -Datasource $PGDataSource -Disk -BackupType ExpressFull
            }
        }
        elseif ($BackupType -eq "Online"){
            foreach ($PGDataSource in $PGDataSources){
                New-DPMRecoveryPoint -Datasource $PGDataSource -Online
            }
        }
    }
    Disconnect-DPMServer
}

function Get-DPMProductionServerTimezoneOffsetinMinutes{
    param(
    [parameter(Mandatory)]$Productionserver,
    [parameter(Mandatory)]$DPMServername
    )
    $DPMServerTimezone = (get-productionserver | where servername -eq $DPMServername).timezoneinformation
    $ProductionServerTimeZone = (Get-ProductionServer | where servername -eq $ProductionServer).TimeZoneInformation
    $DPMServerTimezoneBias.bias - $ProductionServerTimeZone.bias
}

function Set-TervisDPMProtectionGroupScheduleforAllStores {
    param(
        [parameter(Mandatory)]$DPMServername
    )
    Connect-DPMServer -DPMServerName $DPMServername
    $ProtectionGroupList = Get-DPMProtectionGroup
    $DataSources = Get-Datasource
    foreach ($Protectiongroup in $ProtectionGroupList) {
        $ModifiableProtectionGroup = Get-ModifiableProtectionGroup $ProtectionGroup
        $Datasource = $DataSources| where protectiongroupname -eq $ProtectionGroup.Name
        $ProductionServer = $Datasource.Instance
        $TervisStoreProtecitonGroupDefinition = Get-DPMProductionServerDefinition -Name $ProductionServer
        
        $ProductionserverOffset = Get-DPMProductionServerTimezoneOffsetinMinutes -Productionserver $ProductionServer -DPMServername $DPMServername
        Set-TervisDPMProtectionGroupSchedule -ModifiableProtectionGroup $ModifiableProtectionGroup -DPMProtectionGroupSchedulePolicyName $TervisStoreProtecitonGroupDefinition.ProtectionGroupSchedule -ProductionServerTimeZoneOffset $ProductionserverOffset -Online
        Set-ProtectionGroup $ModifiableProtectionGroup
    }
    Disconnect-DPMServer
}

function Install-DPMProtectionAgentBehindFirewall {
    param(
        [parameter(Mandatory)]$Computername,
        [parameter(Mandatory)]$DPMServerName
    )
    $AgentInstallPathRoot = "\\$DPMServerName\c$\Program Files\Microsoft System Center 2016\DPM\DPM\agents\RA"
    $AgentDirectory = (gci $AgentInstallPathRoot\ | where { $_.PSIsContainer } | sort CreationTime -desc | select -f 1).fullname
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

function Invoke-DisableAllDPMAgents {
    param(
        [parameter(Mandatory)]$DPMServerName
    )
    Connect-DPMServer -DPMServerName $DPMServerName
    $ProductionServers = Get-ProductionServer | where ServerProtectionState -eq "HasDatasourcesProtected"
    $ProductionServers | %{Disable-DPMProductionServer -ProductionServer $_ -Confirm:$false}
    Disconnect-DPMServer
}

function Invoke-DisableAllDPMAgents {
    param(
        [parameter(Mandatory)]$DPMServerName
    )
    Connect-DPMServer -DPMServerName $DPMServerName
    $ProductionServers = Get-ProductionServer | where ServerProtectionState -eq "HasDatasourcesProtected"
    $ProductionServers | %{Enable-DPMProductionServer -ProductionServer $_ -Confirm:$false}
    Disconnect-DPMServer
}
 
function Install-OraHollengrenMaintenanceScripts{
    param(
        [parameter(Mandatory)]$Computername
    )
    $MaintenancePlanFile = "$PSScriptRoot\MaintenanceSolution.sql"
    Invoke-Sqlcmd -ServerInstance $ComputerName -InputFile $MaintenancePlanFile
}

#Export-ModuleMember -Function * -Alias * 
#Export-ModuleMember -Function * -Alias *

function Invoke-ConfigureDPMServerProtectionGroupFromDefinitions {
    param(
#        [Parameter(Mandatory)]$DPMServerName,
        [Parameter(Mandatory)]$ProductionServerName
    )
    $ProductionServerDefinition = Get-DPMProductionServerDefinition -Name $ProductionServerName
    $DPMProtectionGroupSchedulePolicyName = $ProductionServerDefinition.ProtectionGroupSchedule
    $DPMServerName = $ProductionServerDefinition.DPMServerName
    $CimSession = New-CimSession -ComputerName $ProductionServerName
    $ProtectableProductionComputerVolumes = Get-Volume -CimSession $CimSession | where {($_.DriveType -eq "Fixed") -and ($_.FilesystemLabel -ne "Recovery") -and ($_.DriveLetter -ne "c") -and ($_.FileSystemLabel -ne "System Reserved")}
    Remove-CimSession $CimSession
    if($ProductionServerDefinition.EnableCompression){
        $EnableCompression = $true
    }
    Else{$EnableCompression = $false}

    Connect-DPMServer $DPMServerName
    if(-not(Get-ProductionServer | where ServerName -eq $ProductionServerName)){
        Set-DPMServernameOnRemoteComputer -Computername $ProductionServerName -DPMServerName $ProductionServerDefinition.DPMServerName
        Invoke-AttachDPMProductionServer -Name $ProductionServerName -DPMServerName $ProductionServerDefinition.DPMServerName
    }
    $ProductionServer = Get-ProductionServer | where ServerName -eq $ProductionServerName
    #$VolumesToProtect = $DataSources | where {($_.Computer -eq $ProductionServerName) -and ($_.Name -match "^[a-zA-Z]:\\")} | select LogicalPath,ProtectionGroup
    $Datasources = Get-DPMDatasource -ProductionServer $ProductionServer -Inquire
    $DefaultDBExceptions = "master","tempdb","model","msdb","ReportServer","ReportServerTempDB" 
    $SQLDatasources = $Datasources | where {($_.ObjectType -match "SQL") -and ($DefaultDBExceptions -notcontains $_.Name)}
    foreach ($ProtectableVolume in $ProtectableProductionComputerVolumes) {
        $ProtectionGroupName = "$ProductionServerName - $($ProtectableVolume.FileSystemLabel)"
        $DatasourceToProtect = $Datasources | where name -like "$($ProtectableVolume.DriveLetter)*"
        Invoke-ProtectDPMDataSource -ProductionServerName $ProductionServerName -DatasourceName $DatasourceToProtect.Name -ProtectionGroupName $ProtectionGroupName -DPMProtectionGroupSchedulePolicyName $DPMProtectionGroupSchedulePolicyName -Online -EnableCompression:$EnableCompression
    }
    if($SQLDatasources){
        foreach ($ProtectableSQLDB in $SQLDatasources) {
            $ProtectionGroupName = "$ProductionServerName - $($ProtectableSQLDB.Name)"
            Invoke-ProtectDPMDataSource -ProductionServerName $ProductionServerName -DatasourceName $ProtectableSQLDB.Name -ProtectionGroupName $ProtectionGroupName -DPMProtectionGroupSchedulePolicyName $DPMProtectionGroupSchedulePolicyName -DataSourceType SQL -Online -EnableCompression:$EnableCompression
        }
    }
    if($ProductionServerDefinition.ChildDatasources){
        $ProtectionGroupName = "$ProductionServerName - FolderLevel"
        Invoke-ProtectDPMDataSource -ProductionServerName $ProductionServerName -ChildDatasourceNames $ProductionServerDefinition.ChildDataSources -ProtectionGroupName $ProtectionGroupName -DPMProtectionGroupSchedulePolicyName $DPMProtectionGroupSchedulePolicyName -Online -EnableCompression:$EnableCompression
    }
    if($ProductionServerDefinition.ProtectSystemDisk){
        $ProtectionGroupName = "$ProductionServerName - SystemDisk"
        Invoke-ProtectDPMDataSource -ProductionServerName $ProductionServerName -DatasourceName "C:\" -ProtectionGroupName $ProtectionGroupName -DPMProtectionGroupSchedulePolicyName $DPMProtectionGroupSchedulePolicyName -Online -EnableCompression:$EnableCompression
    }

    Disconnect-DPMServer
}

function Remove-TervisDPMDatasource {
    param(
        [Parameter(Mandatory)]$ProductionServerName
    )
    $ProductionServerDefinition = Get-DPMProductionServerDefinition -Name $ProductionServerName
    $DPMProtectionGroupSchedulePolicyName = $ProductionServerDefinition.ProtectionGroupSchedule
    $DPMServerName = $ProductionServerDefinition.DPMServerName

    Connect-DPMServer $DPMServerName

    $Protectiongroups = Get-DPMProtectionGroup
    $ProductionServer = Get-ProductionServer | where ServerName -eq $ProductionServerName
    $Datasources = Get-DPMDatasource -ProductionServer $ProductionServer
    $Datasources | %{
        if ($_.Protected){
            $ProtectionGroup = $Protectiongroups | where Name -eq $_.ProtectionGroupName
            $ModifiableProtectionGroup = Get-ModifiableProtectionGroup $Protectiongroup
            Remove-DPMChildDatasource -ProtectionGroup $ModifiableProtectiongroup -ChildDatasource $_ -KeepDiskData -KeepOnlineData
        }
    }

    Disconnect-DPMServer
    
}