library(tidyverse)
library(arrow)

# Load invert taxonomic resources
taxon_resources <- read_csv("../ausinvertraits.addons/taxon_list_for_AusInvertAlign.csv")

write_parquet(taxon_resources)
