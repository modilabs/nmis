################ setup ########################################################
source('setup.R')
source('CONFIG.R')

## FACILITY LEVEL ##
################ EDUCATION ####################################################
source("nmis_functions.R"); source("0_normalize.R"); source("2_outlier_cleaning.R");
source("3_facility_level.R"); source("4_lga_level.R"); source("5_necessary_indicators.R")
source("db.R")

### LOAD DOWNLOAD(ed) EDUCATION DATA
edu_mopup_new <- readRDS(sprintf("%s/education_mopup_new.RDS", CONFIG$MOPUP_DATA_DIR))
edu_mopup_pilot <- readRDS(sprintf("%s/mopup_questionnaire_education_final.RDS",CONFIG$MOPUP_DATA_DIR))
edu_mopup <- readRDS(sprintf("%s/education_mopup.RDS",CONFIG$MOPUP_DATA_DIR))

### 0. NORMALIZE (and merge)
edu_mopup_all <- rbind(normalize_mopup(edu_mopup, 'mopup', 'education'),
                       normalize_mopup(edu_mopup_new, 'mopup_new', 'education'),
                       normalize_mopup(edu_mopup_pilot, 'mopup_pilot', 'education')
                       )
rm(edu_mopup, edu_mopup_new, edu_mopup_pilot)

### 2. OUTLIERS
edu_mopup_all <- education_outlier(edu_mopup_all)

### 3. FACILITY LEVEL
edu_mopup_all <- education_mopup_facility_level(edu_mopup_all)

### 4. LGA LEVEL
## 4.1 load in 2012 data
edu_baseline_2012 <- tbl_df(readRDS(CONFIG$BASELINE_EDUCATION))
edu_baseline_2012 <- normalize_2012(edu_baseline_2012, '2012', 'education')
## 4.2 find common indicators, and rbind the common set
common_indicators <- intersect(names(edu_baseline_2012), names(edu_mopup_all))
edu_all <- rbind(edu_baseline_2012[common_indicators], edu_mopup_all[common_indicators])
rm(edu_baseline_2012, edu_mopup_all)
## 4(1/2) database sync
edu_all <- sync_db(edu_all)

################ HEALTH ####################################################
### LOAD DOWNLOAD(ed) HEALTH DATA
health_mopup <- readRDS(sprintf("%s/health_mopup.RDS",CONFIG$MOPUP_DATA_DIR))
health_mopup_new <- readRDS(sprintf("%s/health_mopup_new.RDS", CONFIG$MOPUP_DATA_DIR))
health_mopup_pilot <- readRDS(sprintf("%s/mopup_questionnaire_health_final.RDS",CONFIG$MOPUP_DATA_DIR))

### 0. NORMALIZE (and merge)
health_mopup_all <- rbind(normalize_mopup(health_mopup, 'mopup', 'health'),
                          normalize_mopup(health_mopup_new, 'mopup_new', 'health'),
                          normalize_mopup(health_mopup_pilot, 'mopup_pilot', 'health')
                          )
rm(health_mopup, health_mopup_new, health_mopup_pilot)

### 2. OUTLIERS
health_mopup_all <- health_outlier(health_mopup_all)

### 3. FACILITY LEVEL
health_mopup_all <- health_mopup_facility_level(health_mopup_all)

### 4. LGA LEVEL
## 4.1 load in 2012 data
health_baseline_2012 <- tbl_df(readRDS(CONFIG$BASELINE_HEALTH))
health_baseline_2012 <- normalize_2012(health_baseline_2012, '2012', 'health')
## 4.2 find common indicators, and rbind the common set
common_indicators <- intersect(names(health_baseline_2012), names(health_mopup_all))
health_all <- rbind(health_baseline_2012[common_indicators], health_mopup_all[common_indicators])
rm(health_baseline_2012, health_mopup_all)
## 4(1/2) sync database
health_all <- sync_db(health_all)
########## WATER ###########################################################
water_baseline_2012 <- tbl_df(readRDS(CONFIG$BASELINE_WATER))
water_baseline_2012 <- normalize_2012(water_baseline_2012, '2012', 'water')
nwater <- get_necessary_indicators()[['facility']][['water']]
## 4(1/2) sync database
water_baseline_2012 <- sync_db(water_baseline_2012)


## Spatial Outlier and LGA aggregation##
source('geospatial_outlier_cleaning.R')

####### Spatial Outlier
all_data <- rbind.fill(edu_all, 
                      health_all,
                      water_baseline_2012) %.% 
                        dplyr::select(unique_lga, survey_id, longitude, latitude) %.%
                        dplyr::tbl_df()
spatial_tagged <- flag_spatial_outliers(all_data, CONFIG$OUTPUT_DIR)


##result of sectors
edu_all <- edu_all %.% dplyr::semi_join(spatial_tagged, by='survey_id')
health_all <- health_all %.% dplyr::semi_join(spatial_tagged, by='survey_id')
water_baseline_2012 <- water_baseline_2012 %.% dplyr::semi_join(spatial_tagged, by='survey_id')

#### save invalid facility name record to separate file
edu_fn_error <- edu_all %.% filter(is.na(facility_name)) %.%
                        dplyr::select(facility_id, survey_id, sector, unique_lga, date_of_survey)
health_fn_error <- health_all %.% filter(is.na(facility_name)) %.%
                        dplyr::select(facility_id, survey_id, sector, unique_lga, date_of_survey)
water_fn_error <- water_baseline_2012 %.% filter(is.na(facility_name)) %.%
                        dplyr::select(facility_id, survey_id, sector, unique_lga, date_of_survey)

write.csv(rbind(edu_fn_error, health_fn_error, water_fn_error), 
          file = sprintf('%s/invalid_facility_names_list.csv', CONFIG$OUTPUT_DIR), 
          row.names=F)
rm(edu_fn_error, health_fn_error, water_fn_error)


edu_all <- edu_all %.% filter(!is.na(facility_name))
health_all <- health_all %.% filter(!is.na(facility_name))
water_baseline_2012 <- water_baseline_2012 %.% filter(!is.na(facility_name))


### education
## 4.3 aggregate
edu_lga <- education_mopup_lga_indicators(edu_all)
edu_gap <- education_gap_sheet_indicators(edu_all)


### 5. OUTPUT 
write.csv(output_indicators(edu_all, 'facility', 'education'), row.names=F,
          file = sprintf('%s/Education_Mopup_and_Baseline_NMIS_Facility.csv', CONFIG$OUTPUT_DIR))
write.csv(output_indicators(edu_lga, 'lga', 'education'), row.names=F,
          file = sprintf('%s/Education_Mopup_and_Baseline_LGA_Aggregations.csv', CONFIG$OUTPUT_DIR))
write.csv(edu_gap, row.names=F,        ## TODO: output_indicators for gap sheets?
          file = sprintf('%s/Education_GAP_SHEETS_LGA_level.csv', CONFIG$OUTPUT_DIR))

### health
## 4.3 aggregate
health_lga <- health_mopup_lga_indicators(health_all)
health_gap <- health_gap_sheet_indicators(health_all)
## 5. OUTPUT
write.csv(output_indicators(health_all, 'facility', 'health'), row.names=F,
          file = sprintf('%s/Health_Mopup_and_Baseline_NMIS_Facility.csv', CONFIG$OUTPUT_DIR))
write.csv(output_indicators(health_lga, 'lga', 'health'), row.names=F,
          file = sprintf('%s/Health_Mopup_and_Baseline_LGA_Aggregations.csv', CONFIG$OUTPUT_DIR))
write.csv(health_gap, row.names=F,
          file = sprintf('%s/Health_GAP_SHEETS_LGA_level.csv', CONFIG$OUTPUT_DIR))

### water 
## 4.2 aggregate
water_lga <- water_lga_indicators(water_baseline_2012)
### 5. Write Out
write.csv(output_indicators(water_baseline_2012, 'facility', 'water'), row.names=F,
          file=sprintf('%s/Water_Mopup_and_Baseline_NMIS_Facility.csv', CONFIG$OUTPUT_DIR))
write.csv(output_indicators(water_lga, 'lga', 'water'), row.names=F,
          file=sprintf('%s/Water_Mopup_and_Baseline_LGA_Aggregations.csv', CONFIG$OUTPUT_DIR))
rm(list=setdiff(ls(), "CONFIG"))

########## EXTERNAL DATA ###################################################
source("nmis_functions.R"); source("0_normalize.R"); source("2_outlier_cleaning.R");
source("3_facility_level.R"); source("4_lga_level.R"); source("5_necessary_indicators.R")

external_data_2012 <- tbl_df(readRDS(CONFIG$BASELINE_EXTERNAL))
external_data_2012 <- normalize_external(external_data_2012)
write.csv(output_indicators(external_data_2012, 'lga', 'overview'), row.names=F,
          file=sprintf('%s/Overview_Baseline_LGA_Aggregations.csv', CONFIG$OUTPUT_DIR))
rm(list=setdiff(ls(), "CONFIG"))


########## Json output ###################################################
source("6_write_Json.R")

invisible(RJson_ouput(OUTPUT_DIR="../static/lgas/", CONFIG))
