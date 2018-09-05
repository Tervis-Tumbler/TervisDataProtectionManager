$DPMProtectionGroupSchedulePolicies = [PSCustomObject][Ordered] @{
        Name = "Stores-ST-21Day-60Min-10pm_Online-21Day-11pm"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "15"
        TimesofDay = "22:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "23:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "Stores-ST-21Day-120Min-10pm_Online-21Day-11pm"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "120"
        TimesofDay = "22:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "23:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "Stores-ST-21day-120Min-12pm_Online-21Day-1am"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "120"
        TimesofDay = "00:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "01:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "ST_21day_60Min_0700_1500_2300_Online_21Day_0000"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "60"
        TimesofDay = "07:00","15:00","23:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "00:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "21day-15Min-12am_8am_4pm"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "15"
        TimesofDay = "00:00,08:00,16:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
    },
    [PSCustomObject][Ordered] @{
        Name = "ST_21day_60Min_0800_1200_1800_Online_21Day_1900"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "60"
        TimesofDay = "08:00","12:00","18:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "19:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "ST_21day_15Min_0800_2000_Online_21Day_2100"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "15"
        TimesofDay = "08:00","20:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "21:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "Online-21Day-12am"
        SynchronizationFrequencyinMinutes = "30"
        TimesofDay = "07:00,15:00,23:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
    },
    [PSCustomObject][Ordered] @{
        Name = "ST_21day_15Min_0700_1500_2300_Online_21Day_0900"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "15"
        TimesofDay = "07:00","15:00","23:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "09:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "ST_21day_60Min_1900_Online_21Day_2100"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "15"
        TimesofDay = "19:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "21:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "ST_21day_15Min_0900_1700_0100_Online_21Day_0400"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "15"
        TimesofDay = "09:00","14:00","01:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "04:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "ST_21day_SyncBeforeRP_0600_1400_2200_Online_21Day_1700"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "0"
        TimesofDay = "06:00","14:00","22:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "17:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "ST_21day_30Min_0600_1400_2200_Online_21Day_0900"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "30"
        TimesofDay = "06:00","14:00","22:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "09:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "ST_21day_30Min_0600_1400_1800_Online_21Day_1200"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "30"
        TimesofDay = "06:00","14:00","18:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "12:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "File_21day_30Min_0700_1500_2300_Online_21Day_0800"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "30"
        TimesofDay = "07:00","15:00","23:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "08:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "File_21day_30Min_0800_1500_2300_Online_21Day_0100"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "30"
        TimesofDay = "07:00","15:00","23:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "01:00"
        OnlineRetentionRangeInDays = "21"
    },
    [PSCustomObject][Ordered] @{
        Name = "ST_21day_60Min_0800_1200_1800_Online_21Day_1000"
        RetentionRangeInDays = "21"
        SynchronizationFrequencyinMinutes = "30"
        TimesofDay = "08:00","12:00","18:00"
        DaysOfWeek = "su","mo","tu","we","th","fr","sa"
        OnlineTOD = "10:00"
        OnlineRetentionRangeInDays = "21"
    }

