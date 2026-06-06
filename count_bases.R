# Clear environment
rm(list = ls())
# Required packages
library(tidyverse)
library(EnvStats)
library(ggpubr)

# Input
# Only take command line input if not running interactively
if (interactive()) {
  wd <- "/project2/noujdine_61/kdeweese/latissima/popgen_redo"
  setwd(wd)
  # Table of raw base counts from each FASTQC result
  tab_file <- "raw_base_counts.txt"
  # Output directory
  outdir <- "s-latissima-popgen/"
} else {
  line_args <- commandArgs(trailingOnly = T)
  tab_file <-  line_args[1]
  outdir <- line_args[2]
}
# Dictionary for subspecies labels
subsp_dict <- c("SL" = "S. latissima", "SA" = "S. angustissima")
reg_dict <- c("GOM" = "Gulf of Maine", "SNE" = "Southern New England")
# Plot variables
txt_size <- 8
n_size <- 3
# Population codes
pop_codes_file <- 
  "/project2/noujdine_61/kdeweese/latissima/compare_vcfs/Saccharina_pop_codes_WHOI.csv"
pop_codes <- read_csv(pop_codes_file)
# Output
bases_plot <- "base_counts.png"
if (dir.exists(outdir)) {bases_plot <- paste0(outdir, "/", bases_plot)}

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
  # Individual = gsub("-CT1-", "-CT-1-", Individual),
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
  mutate(Sample = factor(Sample, levels = unique(Sample))) %>%
  left_join(., pop_codes, by = join_by(Population == Abbreviation))
loc_ord <- df %>%
  distinct(Location, Latitude, Longitude) %>%
  arrange(Latitude, Longitude) %>%
  pull(Location)
df <- df %>%
  mutate(Location = factor(Location, levels = loc_ord))
# Summary data frame of sequenced bases summed by Individual ID
df_sum <- df %>%
  summarize(
    `Bases (Gb)` = sum(`Bases (Gb)`),
    `Coverage (X)` = sum(`Coverage (X)`),
    n = n()/2, # sequencing runs per individual (2x FASTQs)
    .by = c(Individual, Subspecies, Population, Sex, Location, State, Region,
            Latitude, Longitude)
  )

# Plots
# Overall distribution
p_dist <- ggplot(df_sum, aes(x = `Bases (Gb)`)) +
  geom_histogram(aes(group = as.factor(n)), binwidth = 1, position = "identity",
                 alpha = 0.2, color = "darkgrey") +
  geom_density(aes(y = after_stat(count), color = as.factor(n)),
               linewidth = 1, adjust = 0.7) +
  scale_color_discrete(name = "Rounds of\nsequencing") +
  labs(title = "Sequenced bases", y = "Number of individuals") +
  theme_bw() +
  theme(legend.position = "inside", legend.position.inside = c(0.8, 0.8),
        text = element_text(size = txt_size))
# Subspecies violin + box plot
p_subsp <- ggplot(df_sum, aes(x = Subspecies, group = Subspecies,
                              y = `Bases (Gb)`)) +
  geom_violin(trim = F, alpha = 0.3, fill = "darkgrey", scale = "count",
              width = 1.1) +
  geom_boxplot(
    # fill = "white", color = "black",
    varwidth = T, width = 0.15
  ) +
  scale_x_discrete(labels = subsp_dict) +
  # scale_fill_manual(values = "#00AFBB", aesthetics = c("fill", "color")) +
  stat_n_text(y.expand.factor = 0.3, size = n_size) +
  theme_bw() +
  theme(axis.text.x = element_text(face = "italic"),
        legend.position = "none") +
  theme(text = element_text(size = txt_size))
# Boxplots of sequenced bases by population
p_pop <- ggplot(df_sum, aes(x = Location, y = `Bases (Gb)`)) +
  geom_boxplot(aes(fill = Latitude, color = Latitude),
               alpha = 0.2, outlier.alpha = 1) +
  facet_wrap(~ factor(Region, levels = c("SNE", "GOM")),
             labeller = as_labeller(reg_dict),
             scales = "free_x", space = "free_x") +
  scale_x_discrete(labels = ~ str_wrap(., width = 10)) +
  stat_n_text(y.expand.factor = 0.3, size = n_size) +
  theme_bw() +
  theme(text = element_text(size = txt_size))

p1 <- ggarrange(p_dist, p_subsp, widths = c(1.5, 1))
p <- ggarrange(p1, p_pop, ncol = 1)

# Save plots
ggsave(bases_plot, p, bg = "white", height = 8, width = 10)
