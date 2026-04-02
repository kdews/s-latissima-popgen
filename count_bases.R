# Clear environment
rm(list = ls())
# Required packages
library(tidyverse)

setwd("/project2/noujdine_61/kdeweese/latissima/popgen_redo")

# Input
tab_file <- "raw_base_counts.txt"

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
  group_by(Individual, Subspecies, Population) %>%
  summarize(
    `Bases (Gb)` = sum(`Bases (Gb)`),
    `Coverage (X)` = sum(`Coverage (X)`)
  )

# Analysis of sequenced base distribution
summary(df$`Bases (Gb)`)
ggplot(df, aes(x = `Bases (Gb)`)) +
  geom_histogram(bins = 50) +
  geom_vline(xintercept = c(0.6, 1.8), linetype = "dashed", colour = "red") +
  facet_grid(rows = vars(Subspecies)) +
  labs(x = "Total bases (Gbp)", y = "Number of samples",
       title = "Distribution of sequenced bases per sample")

ggplot(df) +
  # geom_histogram(aes(x = `Bases (Gb)`, fill = Batch), show.legend = F)
  geom_histogram(aes(x = `Coverage (X)`, fill = Subspecies), show.legend = F) +
  # geom_histogram(aes(x = `Bases (Gb)`, fill = Population), show.legend = F)
  # geom_histogram(aes(x = `Bases (Gb)`, fill = Index), show.legend = F)
  facet_grid(rows = vars(Batch))
  # facet_grid(rows = vars(Instrument))
  # facet_grid(rows = vars(Plate))
  # facet_grid(rows = vars(Sex))
  # facet_grid(rows = vars(Library_Type))

ggplot(df, aes(x = Sample, y = `Bases (Gb)`)) +
  # geom_col(aes(fill = paste(Library_Type, Plate, Lane, Instrument, sep = "_"))) +
  # geom_col(aes(fill = Plate)) +
  # geom_col(aes(fill = Lane)) +
  # geom_col(aes(fill = Instrument)) +
  geom_col(aes(fill = paste(Plate, Lane, Instrument, sep = "_"))) +
  # geom_col(aes(fill = Population), show.legend = F) +
  # facet_grid(rows = vars(Class)) +
  # facet_grid(rows = vars(Population)) +
  # facet_grid(rows = vars(Subspecies)) +
  # facet_grid(rows = vars(Subspecies), space = "free_y", scale = "free_y") +
  scale_y_continuous(n.breaks = 10) +
  theme_classic() +
  theme(
    axis.text.x = element_blank(),
    axis.ticks.x = element_blank(),
    # axis.text.y = element_blank(),
    panel.grid.major.y = element_line()
  )

summary(df_sum$`Bases (Gb)`)
ggplot(df_sum, aes(x = `Bases (Gb)`)) +
  # geom_histogram(aes(fill = Subspecies), bins = 50) +
  geom_histogram(aes(fill = Population), bins = 50, show.legend = F) +
  geom_vline(xintercept = c(0.6, 1.8), linetype = "dashed", colour = "red") +
  labs(x = "Total bases (Gbp)", y = "Number of individuals",
       title = "Distribution of sequenced bases per individual")

