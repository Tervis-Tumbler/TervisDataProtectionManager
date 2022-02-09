$ProductionServerDefinitions = [PSCustomObject][Ordered] @{
        Name = "Cattools"
        ProtectionGroupSchedule= "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        OffsetinMinutes = "10"
        DPMServerName = "inf-scdpmfs03.prv"
        ChildDataSources = "c:\Program Files (x86)\CatTools3"
    },
    [PSCustomObject][Ordered] @{
        Name = "inf-dc01"
        ProtectionGroupSchedule= "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmsql03.tervis.prv"
        ChildDataSources = "System Protection","C:\"
    },
    [PSCustomObject][Ordered] @{
        Name = "epdm"
        ProtectionGroupSchedule= "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmfs03.tervis.prv"
        ChildDataSources = "c:\DB Backup","C:\EPDM 2012 sp3.0","C:\EPDM_Archive","c:\EPDM_Data","c:\EPDM_Data_Logs","c:\EPDM_License","c:\inetpub","c:\Recovery","c:\Sandbox_2","c:\scripts","c:\Solidworks 2013 Enterprise PDM","c:\Solidworks 2016 Upgrade","c:\Tools"
    },
    [PSCustomObject][Ordered] @{
        Name = "exchange2016"
        ProtectionGroupSchedule= "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmfs03.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "inf-exchange01"
        ProtectionGroupSchedule= "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmfs03.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "inf-WorldShip"
        ProtectionGroupSchedule= "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmfs04.tervis.prv"
        ProtectSystemDisk = $true
    },
    [PSCustomObject][Ordered] @{
        Name = "WDS"
        ProtectionGroupSchedule= "ST_21day_60Min_1900_Online_21Day_2100"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "WDS2012r2"
        ProtectionGroupSchedule= "ST_21day_60Min_1900_Online_21Day_2100"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmfs03.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "prd-wcsapp01"
        ProtectionGroupSchedule= "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmFS03.tervis.prv"
        ChildDataSources = "C:\QcSoftware"
    },
    [PSCustomObject][Ordered] @{
        Name = "tfs2012"
        ProtectionGroupSchedule= "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmfs04.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "SQLRMSHQ"
        ProtectionGroupSchedule= "ST_21day_15Min_0900_1700_0100_Online_21Day_0400"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "SQL"
        ProtectionGroupSchedule= "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "Sharepoint2007"
        ProtectionGroupSchedule= "ST_21day_SyncBeforeRP_0600_1400_2200_Online_21Day_1700"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "scheduledtasks"
        ProtectionGroupSchedule= "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmfs03.tervis.prv"
        ChildDataSources = "C:\Scripts"
    },
    [PSCustomObject][Ordered] @{
        Name = "rdmanager"
        ProtectionGroupSchedule= "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmfs04.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "prd-progis01"
        ProtectionGroupSchedule= "ST_21day_15Min_0900_1700_0100_Online_21Day_0400"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmfs04.tervis.prv"
        ChildDataSources = "C:\Program Files (x86)\ConnectShip\Progistics"
    },
    [PSCustomObject][Ordered] @{
        Name = "powershell"
        ProtectionGroupSchedule= "ST_21day_SyncBeforeRP_0600_1400_2200_Online_21Day_1700"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmfs04.tervis.prv"
        ChildDataSources = "c:\scripts","c:\inetpub"
    },
    [PSCustomObject][Ordered] @{
        Name = "passwordstate"
        ProtectionGroupSchedule= "File_21day_30Min_0800_1500_2300_Online_21Day_0100"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmfs04.tervis.prv"
        ChildDatasources = "c:\inetpub"
        EnableCompression = $true
    },
    [PSCustomObject][Ordered] @{
        Name = "inf-orabackups"
        ProtectionGroupSchedule = "ST_10day_30Min_0800_1200_1800_Online_10Day_1000" 
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpm201902.tervis.prv"
        ExcludedDatasources = "D","O","E"
    },
    [PSCustomObject][Ordered] @{
        Name = "p-octopusdeploy"
        ProtectionGroupSchedule = "ST_21day_30Min_0600_1400_2200_Online_21Day_0900"
        OffsetinMinutes = "30"
        DPMServerName = "inf-scdpmfs04.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "inf-dfshq1"
        ProtectionGroupSchedule= "File_21day_30Min_0700_1500_2300_Online_21Day_0800"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpm201901.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "inf-dfshq2"
        ProtectionGroupSchedule= "File_21day_30Min_0700_1500_2300_Online_21Day_0800"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmfs01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "inf-dfshq3"
        ProtectionGroupSchedule= "File_21day_30Min_0800_1500_2300_Online_21Day_0100"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpm201901.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "inf-dfs2"
        ProtectionGroupSchedule= "File_21day_30Min_0700_1500_2300_Online_21Day_0800"
        OffsetinMinutes = "60"
        DPMServerName = "inf-scdpmfs03.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "P-WCS"
        ProtectionGroupSchedule= "File_21day_30Min_0700_1500_2300_Online_21Day_0800"
        OffsetinMinutes = "60"
        DPMServerName = "inf-scdpmfs03.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "DFS-10"
        ProtectionGroupSchedule= "File_21day_30Min_0700_1500_2300_Online_21Day_0800"
        OffsetinMinutes = "60"
        DPMServerName = "inf-scdpmfs01.tervis.prv"
    },
    [PSCustomObject][Ordered] @{
        Name = "INF-FedexSM01"
        ProtectionGroupSchedule= "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        OffsetinMinutes = "0"
        DPMServerName = "inf-scdpmsql01.tervis.prv"
        ChildDataSources = "C:\ProgramData\FedEx"
    }

