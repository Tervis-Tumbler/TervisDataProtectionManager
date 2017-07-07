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