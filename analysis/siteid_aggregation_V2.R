# Site Reporting Aggreagation Tool
# REACH YEMEN Team - alberto.gualtieri@reach-initiative.org
# V1
# 13/01/2020

rm(list=ls())
today <- Sys.Date()

### Download custom packages
# devtools::install_github("mabafaba/hypegrammaR")
# devtools::install_github("mabafaba/composR", force = T, build_vignettes = T)
# devtools::install_github("mabafaba/xlsformfill", force = T, build_vignettes = T)

### Load required library
library("tidyverse")
library("hypegrammaR")
library("xlsformfill")
library("openxlsx")
library("stringr")
library("srvyr")
library("reshape")

### Load source
source("./R/functions/functions.R")
source("./R/functions/from_hyperanalysis_to_datamerge.R")
source("./R/functions/moveme.R")
source("./R/add_locations.R")

### Load data and filter out "informal"
response <- read.xlsx("./data/CCCM_SiteReporting_All Internal (WithID)_2020-10-11.xlsx")
#response <- filter(response, response$a9_formal_informal == "formal")


### Load questionnaire
questions <- read.csv("./data/kobo/questions.csv", check.names = F)
choices <- read.csv("./data/kobo/choices.csv", check.names = F)
external_choices <- read.csv("./data/kobo/external_choices.csv", check.names = F)

questionnaire <- load_questionnaire(response,
                                    questions,
                                    choices,
                                    choices.label.column.to.use = "label::english")

### Load Data Analysis Plan
dap <- load_analysisplan("./data/cccm_analysis_plan_v3_governorate.csv")

### Create sampling function and load the weights (useless but the analysis output function requires it)
#sf <- read.csv("./data/sf.csv")
#sf <- sf[!duplicated(sf), ]

#response$stratum_id <- response$a4_site_code
#response$stratum_id <- str_replace(response$stratum_id, " - ", "_")

#weight.function <- map_to_weighting(sf, "stratum_id", "population", "stratum_id")


### Fix old entries with new names
response$c10_primary_latrine_type <- ifelse(response$c10_primary_latrine_type == "open_air", "open_defaction", response$c10_primary_latrine_type)


### Create extra variables
### Issues with eviction but having tennecy agreement
response <- mutate(response, agreement_with_issue= ifelse((response$c3_tenancy_agreement_for_at_least_6_months == "yes" & 
                                                             response$f1_threats_to_the_site.eviction == "1"), "1", "0"))

response <- mutate(response, agreement_with_issue = ifelse((response$c3_tenancy_agreement_for_at_least_6_months == "no"), NA, agreement_with_issue))

#check <- select(response, c("a1_governorate_name", "c3_tenancy_agreement_for_at_least_6_months", "f1_threats_to_the_site.eviction", "agreement_with_issue"))
#check <- check %>% filter(a1_governorate_name == "Dhamar" | a1_governorate_name == "Sana'a")

### Max number of site by governorate
response$site_num <- 1
max_dist <- aggregate(response$site_num, list(governorate = response$a1_governorate_name), sum)
names(max_dist)[names(max_dist) == "x"] <- "tot_sites"

### Total number of households and individuals by district
tot_hh <- aggregate(as.numeric(response$a7_site_population_hh), list(governorate = response$a1_governorate_name), sum)
names(tot_hh)[names(tot_hh) == "x"] <- "tot_hh"

tot_ind <- aggregate(as.numeric(response$a7_site_population_individual), list(governorate = response$a1_governorate_name), sum)
names(tot_ind)[names(tot_ind) == "x"] <- "tot_ind"

#### Most common district of origin analysis
getmode <- function(v) {
  uniqv <- unique(v)
  uniqv[which.max(tabulate(match(v, uniqv)))]
}

external_choices <- filter(external_choices, external_choices$list_name == "district")

### Weighted analysis
reported_dist <- select(response, c("a1_governorate_name", "a7_site_population_individual", "d2_1_most_common_district_of_idp_origin"))

names(external_choices)[names(external_choices) == "name"] <- "d2_1_most_common_district_of_idp_origin"

reported_dist$d2_1_most_common_district_of_idp_origin <- external_choices$`label::english`[match(reported_dist$d2_1_most_common_district_of_idp_origin, 
                                                                                                 external_choices$d2_1_most_common_district_of_idp_origin)]


most_reported_dis_wgt <- aggregate(as.numeric(reported_dist$a7_site_population_individual), 
                                   list(governorate = reported_dist$a1_governorate_name, most_district = reported_dist$d2_1_most_common_district_of_idp_origin), sum)

most_reported_dis_wgt <- most_reported_dis_wgt %>% group_by(governorate) %>% top_n(1, x)

most_reported_dis_wgt$x <- NULL



### Most common reason for leaving
leaving_reas <- select(response, c("a1_governorate_name", "a7_site_population_individual", "d1_most_common_reason_idps_left_place_of_origin"))

names(choices)[names(choices) == "name"] <- "d1_most_common_reason_idps_left_place_of_origin"

leaving_reas$d1_most_common_reason_idps_left_place_of_origin <- choices$`label::english`[match(leaving_reas$d1_most_common_reason_idps_left_place_of_origin, 
                                                                                                 choices$d1_most_common_reason_idps_left_place_of_origin)]

most_reported_leave_wgt <- aggregate(as.numeric(leaving_reas$a7_site_population_individual),
                                     list(governorate = leaving_reas$a1_governorate, most_leave_reason = leaving_reas$d1_most_common_reason_idps_left_place_of_origin), sum)

most_reported_leave_wgt <- most_reported_leave_wgt %>% group_by(governorate) %>% top_n(1, x)

most_reported_leave_wgt$x <- NULL


### Most common intention in the next three months
intentions <- select(response, c("a1_governorate_name", "a7_site_population_hh", "d3_most_common_intention_in_next_three_months"))


names(choices)[names(choices) == "d1_most_common_reason_idps_left_place_of_origin"] <- "d3_most_common_intention_in_next_three_months"

intentions$d3_most_common_intention_in_next_three_months <- choices$`label::english`[match(intentions$d3_most_common_intention_in_next_three_months, 
                                                                                               choices$d3_most_common_intention_in_next_three_months)]


most_reported_int_wgt <- aggregate(as.numeric(intentions$a7_site_population_hh),
                                   list(governorate = intentions$a1_governorate, most_intention = intentions$d3_most_common_intention_in_next_three_months), sum)

most_reported_int_wgt <- most_reported_int_wgt %>% group_by(governorate) %>% top_n(1, x)

most_reported_int_wgt$x <- NULL



### Join everything
library("plyr")

external_analysis <- join_all(list(max_dist, tot_hh, tot_ind, most_reported_dis_wgt, most_reported_int_wgt, most_reported_leave_wgt),
                              by = "governorate")

### Label full dataset before running the analysis
names(choices)[names(choices) == "d3_most_common_intention_in_next_three_months"] <- "name"
response_ren <- response

response_ren <- response_ren[moveme(names(response_ren), "uuid first")]
response_ren[18:147] <- choices$`label::english`[match(unlist(response_ren[18:147]), choices$name)]




### Launch Analysis Script
analysis <- from_analysisplan_map_to_output(data = response_ren,
                                            analysisplan = dap,
                                            weighting = NULL,
                                            questionnaire = questionnaire)
                                        
                                                         


## SUMMARY STATS LIST ##
summary.stats.list <- analysis$results


## SUMMARY STATS LIST FORMATTED 
summarystats <- summary.stats.list %>%
  #lapply((map_to_labeled),questionnaire) %>% 
  resultlist_summary_statistics_as_one_table

write.csv(summarystats, paste0("./output/summarystats_final_",today,".csv"))



### Load the results and lunch data merge function
final_analysis <- read.csv(paste0("./output/summarystats_final_",today,".csv"), stringsAsFactors = F)

final_melted_analysis <- from_hyperanalysis_to_datamerge(final_analysis)

#### Multiply everything by 100, round everything up, and replace NAs with 0
final_dm <- cbind(final_melted_analysis[1], sapply(final_melted_analysis[-1],function(x) x*100))

final_dm[,-1] <- round(final_dm[,-1],0)

final_dm[is.na(final_dm)] <- 0


### Join indicators not analyzed by hypegrammaR
names(final_dm)[names(final_dm) == "independent.var.value"] <- "governorate"
data_merge <- left_join(final_dm, external_analysis, by = "governorate")

#write.xlsx(data_merge, paste0("./output/governorate_data_merge_",today,".xlsx"))
#browseURL(paste0("./output/governorate_data_merge_",today,".xlsx"))


### Add maps to the fina data merge and save it as .csv file
data_merge$`@map` <- paste0("./maps/YEM_CCCM_",data_merge$governorate,".pdf")

names(data_merge) <- tolower(names(data_merge))

write.csv(data_merge, paste0("./output/governorate_data_merge_",today,".csv"), row.names = F)                     
browseURL(paste0("./output/cccm_governorate_full_merge_",today,".csv"))

