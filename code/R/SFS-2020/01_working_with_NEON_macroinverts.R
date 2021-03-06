## ----load libraries---------------------------------------------------------

# clean out workspace

#rm(list = ls()) # OPTIONAL - clear out your environment
#gc()            # Uncomment these lines if desired

# load libraries 
library(tidyverse)
library(neonUtilities)


# source .r file with my NEON_TOKEN
# source("my_neon_token.R") # OPTIONAL - load NEON token
# See: https://www.neonscience.org/neon-api-tokens-tutorial



## ----download-data----------------------------------------------------------

# Macroinvert dpid
my_dpid <- 'DP1.20120.001'

# list of sites
my_site_list <- c('ARIK', 'POSE', 'MAYF')

# get all tables for these sites from the API -- takes < 1 minute
all_tabs_inv <- neonUtilities::loadByProduct(
  dpID = my_dpid,
  site = my_site_list,
  #token = NEON_TOKEN, #Uncomment to use your token
  check.size = F)



## ----download-overview------------------------------------------------------


# what tables do you get with macroinvertebrate 
# data product
names(all_tabs_inv)

# extract items from list and put in R env. 
all_tabs_inv %>% list2env(.GlobalEnv)

# readme has the same informaiton as what you 
# will find on the landing page on the data portal

# The variables file describes each field in 
# the returned data tables
head(variables_20120)

# The validation file provides the rules that 
# constrain data upon ingest into the NEON database:
head(validation_20120)

# the categoricalCodes file provides controlled 
# lists used in the data
head(categoricalCodes_20120)



## ----munging-and-organizing-------------------------------------------------

# extract year from date, add it as a new column
inv_fieldData <- inv_fieldData %>%
  mutate(
    year = collectDate %>% 
      lubridate::as_date() %>% 
      lubridate::year())


# extract location data into a separate table
table_location <- inv_fieldData %>%
  
  # keep only the columns listed below
  select(siteID, 
         domainID,
         namedLocation, 
         decimalLatitude, 
         decimalLongitude, 
         elevation) %>%
  
  # keep rows with unique combinations of values, 
  # i.e., no duplicate records
  distinct()



# create a taxon table, which describes each 
# taxonID that appears in the data set
# start with inv_taxonomyProcessed
table_taxon <- inv_taxonomyProcessed %>%

  # keep only the coluns listed below
  select(acceptedTaxonID, taxonRank, scientificName,
         order, family, genus, 
         identificationQualifier,
         identificationReferences) %>%

  # remove rows with duplicate information
  distinct()



# taxon table information for all taxa in 
# our database can be downloaded here:
# takes 1-2 minutes
# full_taxon_table_from_api <- neonUtilities::getTaxonTable("MACROINVERTEBRATE", token = NEON_TOKEN)



# Make the observation table.
# start with inv_taxonomyProcessed
table_observation <- inv_taxonomyProcessed %>% 
  
  # select a subset of columns from
  # inv_taxonomyProcessed
  select(uid,
         sampleID,
         domainID,
         siteID,
         namedLocation,
         collectDate,
         subsamplePercent,
         individualCount,
         estimatedTotalCount,
         acceptedTaxonID,
         order, family, genus, 
         scientificName,
         taxonRank) %>%
  
  # Join the columns selected above with two 
  # columns from inv_fieldData (the two columns 
  # are sampleID and benthicArea)
  left_join(inv_fieldData %>% 
              select(sampleID, eventID, year, 
                     habitatType, samplerType,
                     benthicArea)) %>%
  
  # some new columns called 'variable_name', 
  # 'value', and 'unit', and assign values for 
  # all rows in the table.
  # variable_name and unit are both assigned the 
  # same text strint for all rows. 
  mutate(inv_dens = estimatedTotalCount / benthicArea,
         inv_dens_unit = 'count per square meter')



# extract sample info
table_sample_info <- table_observation %>%
  select(sampleID, domainID, siteID, namedLocation, 
         collectDate, eventID, year, 
         habitatType, samplerType, benthicArea, 
         inv_dens_unit) %>%
  distinct()



# remove singletons and doubletons
# create an occurrence summary table
taxa_occurrence_summary <- table_observation %>%
  select(sampleID, acceptedTaxonID) %>%
  distinct() %>%
  group_by(acceptedTaxonID) %>%
  summarize(occurrences = n())

# filter out taxa that are only observed 1 or 2 times
taxa_list_cleaned <- taxa_occurrence_summary %>%
  filter(occurrences > 2)

# filter observation table based on taxon list above
table_observation_cleaned <- table_observation %>%
  filter(acceptedTaxonID %in%
             taxa_list_cleaned$acceptedTaxonID,
         !sampleID %in% c("MAYF.20190729.CORE.1",
                          "POSE.20160718.HESS.1")) 
                      #this is an outlier sampleID


# some summary data
sampling_effort_summary <- table_sample_info %>%
  
  # group by siteID, year
  group_by(siteID, year, samplerType) %>%
  
  # count samples and habitat types within each event
  summarise(
    event_count = eventID %>% unique() %>% length(),
    sample_count = sampleID %>% unique() %>% length(),
    habitat_count = habitatType %>% 
        unique() %>% length())

View(sampling_effort_summary)



## ----long-data--------------------------------------------------------------

# no. taxa by rank by site
table_observation_cleaned %>% 
  group_by(domainID, siteID, taxonRank) %>%
  summarize(
    n_taxa = acceptedTaxonID %>% 
        unique() %>% length()) %>%
  ggplot(aes(n_taxa, taxonRank)) +
  facet_wrap(~ domainID + siteID) +
  geom_col()

## ----long-data-2------------------------------------------------------------
# library(scales)
# sum densities by order for each sampleID
table_observation_by_order <- 
    table_observation_cleaned %>% 
    filter(!is.na(order)) %>%
    group_by(domainID, siteID, year, 
             eventID, sampleID, habitatType, order) %>%
    summarize(order_dens = sum(inv_dens, na.rm = TRUE))
  
  
# rank occurrence by order
table_observation_by_order %>% head()


# stacked rank occurrence plot
table_observation_by_order %>%
  group_by(order, siteID) %>%
  summarize(
    occurrence = (order_dens > 0) %>% sum()) %>%
    ggplot(aes(
        x = reorder(order, -occurrence), 
        y = occurrence,
        color = siteID,
        fill = siteID)) +
    geom_col() +
    theme(axis.text.x = 
              element_text(angle = 45, hjust = 1))


## ----long-data-3------------------------------------------------------------
# faceted densities plot
table_observation_by_order %>%
  ggplot(aes(
    x = reorder(order, -order_dens), 
    y = log10(order_dens),
    color = siteID,
    fill = siteID)) +
  geom_boxplot(alpha = .5) +
  facet_grid(siteID ~ .) +
  theme(axis.text.x = 
            element_text(angle = 45, hjust = 1))





## ----make-wide--------------------------------------------------------------


# select only site by species density info and remove duplicate records
table_sample_by_taxon_density_long <- table_observation_cleaned %>%
  select(sampleID, acceptedTaxonID, inv_dens) %>%
  distinct() %>%
  filter(!is.na(inv_dens))

# table_sample_by_taxon_density_long %>% nrow()
# table_sample_by_taxon_density_long %>% distinct() %>% nrow()



# pivot to wide format, sum multiple counts per sampleID
table_sample_by_taxon_density_wide <- table_sample_by_taxon_density_long %>%
  tidyr::pivot_wider(id_cols = sampleID, 
                     names_from = acceptedTaxonID,
                     values_from = inv_dens,
                     values_fill = list(inv_dens = 0),
                     values_fn = list(inv_dens = sum)) %>%
  column_to_rownames(var = "sampleID") 

# checl col and row sums
colSums(table_sample_by_taxon_density_wide) %>% min()
rowSums(table_sample_by_taxon_density_wide) %>% min()



## ----calc-alpha-------------------------------------------------------------

table_sample_by_taxon_density_wide %>%
  vegetarian::d(lev = 'alpha', q = 0)



## ----simulated-abg----------------------------------------------------------

# even distribution, order q = 0 diversity = 10 
vegetarian::d(
  data.frame(spp.a = 10, spp.b = 10, spp.c = 10, 
             spp.d = 10, spp.e = 10, spp.f = 10, 
             spp.g = 10, spp.h = 10, spp.i = 10, 
             spp.j = 10),
  q = 0, 
  lev = "alpha")

# even distribution, order q = 1 diversity = 10
vegetarian::d(
  data.frame(spp.a = 10, spp.b = 10, spp.c = 10, 
             spp.d = 10, spp.e = 10, spp.f = 10, 
             spp.g = 10, spp.h = 10, spp.i = 10, 
             spp.j = 10),
  q = 1, 
  lev = "alpha")

# un-even distribution, order q = 0 diversity = 10
vegetarian::d(
  data.frame(spp.a = 90, spp.b = 2, spp.c = 1, 
             spp.d = 1, spp.e = 1, spp.f = 1, 
             spp.g = 1, spp.h = 1, spp.i = 1, 
             spp.j = 1),
  q = 0, 
  lev = "alpha")

# un-even distribution, order q = 1 diversity = 1.72
vegetarian::d(
  data.frame(spp.a = 90, spp.b = 2, spp.c = 1, 
             spp.d = 1, spp.e = 1, spp.f = 1, 
             spp.g = 1, spp.h = 1, spp.i = 1, 
             spp.j = 1),
  q = 1, 
  lev = "alpha")



## ----compare-q-NEON---------------------------------------------------------

# Nest data by siteID
data_nested_by_siteID <- table_sample_by_taxon_density_wide %>%
  tibble::rownames_to_column("sampleID") %>%
  left_join(table_sample_info %>% 
                select(sampleID, siteID)) %>%
  tibble::column_to_rownames("sampleID") %>%
  nest(data = -siteID)

# apply the calculation by site  
data_nested_by_siteID %>% mutate(
  alpha_q0 = purrr::map_dbl(
    .x = data,
    .f = ~ vegetarian::d(abundances = .,
    lev = 'alpha', 
    q = 0)))

# Note that POSE has the highest mean diversity



# Now calculate alpha, beta, and gamma using orders 0 and 1,
# Note that I don't make all the argument assignments as explicitly here
diversity_partitioning_results <- 
    data_nested_by_siteID %>% 
    mutate(
        n_samples = purrr::map_int(data, ~ nrow(.)),
        alpha_q0 = purrr::map_dbl(data, ~vegetarian::d(
            abundances = ., lev = 'alpha', q = 0)),
        alpha_q1 = purrr::map_dbl(data, ~ vegetarian::d(
            abundances = ., lev = 'alpha', q = 1)),
        beta_q0 = purrr::map_dbl(data, ~ vegetarian::d(
            abundances = ., lev = 'beta', q = 0)),
        beta_q1 = purrr::map_dbl(data, ~ vegetarian::d(
            abundances = ., lev = 'beta', q = 1)),
        gamma_q0 = purrr::map_dbl(data, ~ vegetarian::d(
            abundances = ., lev = 'gamma', q = 0)),
        gamma_q1 = purrr::map_dbl(data, ~ vegetarian::d(
            abundances = ., lev = 'gamma', q = 1)))


diversity_partitioning_results %>% select(-data) %>% print()

# Note that POSE has the highest mean diversity



## ----local-regional-var, echo=F---------------------------------------------

##########################################################
# local and regional scale variability
#########################################

# This doesn't make sense to do for macroinverts unless we can get 
# finer spatial resolution. 

# devtools::install_github("sokole/ltermetacommunities/ltmc")
# library(ltmc)
# 
# # Variability in aggregate biomass folloing
# # Wang and Loreau (2014)
# metacommunity_variability_results_POSE <- table_observation %>%
#   filter(!is.na(inv_dens), siteID == "POSE") %>%
#   ltmc::metacommunity_variability(
#     data_long = .,
#     time_step_col_name = "year",
#     site_id_col_name = "namedLocation",
#     taxon_id_col_name = "order",
#     biomass_col_name = "inv_dens",
#     variability_type = "agg")



## ----NMDS-------------------------------------------------------------------


# create ordination using NMDS
my_nmds_result <- table_sample_by_taxon_density_wide %>% vegan::metaMDS()

# plot stress
my_nmds_result$stress
p1 <- vegan::ordiplot(my_nmds_result)
vegan::ordilabel(p1, "species")

# merge NMDS scores with sampleID information for plotting
nmds_scores <- my_nmds_result %>% vegan::scores() %>%
  as.data.frame() %>%
  tibble::rownames_to_column("sampleID") %>%
  left_join(table_sample_info)


# # How I determined the outlier(s)
nmds_scores %>% arrange(desc(NMDS1)) %>% head()
nmds_scores %>% arrange(desc(NMDS1)) %>% tail()


# Plot samples in community composition space by year
nmds_scores %>%
  ggplot(aes(NMDS1, NMDS2, color = siteID, 
             shape = samplerType)) +
  geom_point() +
  facet_wrap(~ as.factor(year))

# Plot samples in community composition space
# facet by siteID and habitat type
# color by year
nmds_scores %>%
  ggplot(aes(NMDS1, NMDS2, color = as.factor(year), 
             shape = samplerType)) +
  geom_point() +
  facet_grid(habitatType ~ siteID, scales = "free")
  




