# Clear environment
rm(list = ls())
# Required packages
library(tidyverse)
library(ggpubr)

setwd("/project2/noujdine_61/kdeweese/latissima/popgen_redo")

# Input
tab_file <- "raw_base_counts.txt"
bases_plot <- "base_counts.png"

# Data wrangling
df <- read_delim(tab_file, col_names = c("Sample", "Value", "Unit"))
df <- df %>% mutate(
  # Convert all to Gb
  `Bases (Gb)` = case_when(
    Unit == "Gbp" ~ Value,
    Unit == "Mbp" ~ Value / 1000,
    Unit == "Kbp" ~ Value / 1000000,
    TRUE ~ NA_real_,
  ),
  `Coverage (X)` = `Bases (Gb)`/(615*10^-3),
  # Get metadata from sample names
  Individual = str_split_i(Sample, "_", 1),
  Individual = gsub("-CT1-", "-CT-1-", Individual),
  Individual = gsub("LIS-F1-3", "SL-SNE-1-FG-3", Individual),
  Individual = gsub("-Female", "-FG-", Individual),
  Subspecies = str_split_i(Individual, "-", 1),
  Population = str_split_i(Individual, "-", 2),
  Sex = gsub(".*-([FM]G)-.*", "\\1", Individual),
  Library = str_split_i(Sample, "_", 2),
  Library_Type = substr(Library, 1, 1),
  Instrument = str_split_i(Sample, "_", 3),
  Index = str_split_i(Sample, "_", 4),
  Plate = str_split_i(Sample, "_", 5),
  Lane = str_split_i(Sample, "_", 6),
  Batch = paste(Library_Type, Plate, Lane, Instrument, sep = "_")
) %>%
  # Mark low sequenced
  mutate(Class = case_when(`Bases (Gb)` < 3 ~ "Low", .default = "High"))
df <- df %>%
  arrange(`Bases (Gb)`) %>%
  mutate(Sample = factor(Sample, levels = unique(Sample)))
# Summary data frame of sequenced bases summed by Individual ID
df_sum <- df %>%
  summarize(
    `Bases (Gb)` = sum(`Bases (Gb)`),
    `Coverage (X)` = sum(`Coverage (X)`),
    n = n()/2,
    .by = c(Individual, Subspecies, Population)
  )

# Analysis of sequenced base distribution
summary(df$`Bases (Gb)`)
p_samp <- ggplot(df, aes(x = `Bases (Gb)`)) +
  geom_histogram(aes(fill = Subspecies), bins = 50) +
  labs(x = "Total bases (Gbp)", y = "Number of samples",
       title = "Distribution of sequenced bases per FASTQ")

summary(df_sum$`Bases (Gb)`)
p_indiv <- ggplot(df_sum, aes(x = `Bases (Gb)`)) +
  geom_histogram(aes(fill = Subspecies), bins = 50) +
  labs(x = "Total bases (Gbp)", y = "Number of individuals",
       title = "Distribution of sequenced bases per individual")

ggplot(df_sum, aes(x = as.factor(n), y = `Bases (Gb)`)) +
  geom_boxplot() +
  geom_jitter(aes(color = Subspecies))

p <- ggarrange(p_samp, p_indiv, common.legend = T)

ggsave(bases_plot, p, bg = "white", width = 10)
