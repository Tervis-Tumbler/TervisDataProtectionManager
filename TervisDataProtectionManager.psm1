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
        $DPMDBName
    )
    Invoke-SQL -dataSource inf-scdpm201601 -database DPMDB_INF_SCDPM201601 -sqlCommand @"
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

function Move-DPMAgents {
    param (
        $ComputerName,
        $OldComputerName
    )

    Import-DataProtectionManagerModule -ComputerName $OldComputerName -Prefix Old
    Import-DataProtectionManagerModule -ComputerName $ComputerName

    $AgentsOld = Get-OldProductionServer
    $Agents = Get-ProductionServer

    $AgentsToMove = Compare-Object -ReferenceObject $AgentsOld -DifferenceObject $Agents -Property Name | 
    where SideIndicator -eq "<=" |
    where Name -NE $OldComputerName |
    Select -ExpandProperty Name

    Set-DPMServernameOnRemoteComputer -Computername $AgentsToMove -DPMServerName $ComputerName

    foreach ($Agent in $AgentsToMove) {
        Invoke-AttachDPMProductionServer -DPMServerName $ComputerName -Name $Agent        
    }

    $ProductionServers = Get-ProductionServer
    $ProductionServers | % { $_.GetDataSources() }

    $OldProtectionGroup = Get-OldProtectionGroup -DPMServerName $OldComputerName
    $ProtectionGroup = Get-ProtectionGroup -DPMServerName $ComputerName

    #Compare-Object -ReferenceObject $OldProtectionGroup -DifferenceObject $ProtectionGroup -Property Name -IncludeEqual

    $ProtectionGroupNamesToCreate = Compare-Object -ReferenceObject $OldProtectionGroup -DifferenceObject $ProtectionGroup -Property Name |
    where SideIndicator -eq "<=" |
    Select -ExpandProperty Name

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
    $AttachProductionServerScriptPath = 'C:\Program Files\Microsoft System Center 2016\DPM\DPM\bin\Attach-ProductionServer.ps1'
    
    $Command = "& `"$AttachProductionServerScriptPath`" -DPMServerName $DPMServerName -PSName $Name -UserName $($Credential.Username) -Password $($Credential.GetNetworkCredential().Password) -Domain tervis.prv"
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

Export-ModuleMember -Function * -Alias * 