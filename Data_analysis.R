library(ggplot2)
library(patchwork)

output_dir <- file.path(getwd(), "plot")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

data <- read.csv(file.path(getwd(), "data", "processed", "model_table.csv"))
stopifnot(!anyNA(data$y), setequal(data$y, c(0, 1)))
data$group <- factor(data$y, levels = c(0, 1), labels = c("Background (0)", "Heracleum (1)"))

climate <- c("bio1_temp_mean_c", "bio4_temp_sd_x100", "bio8_temp_wettest_quarter_c",
             "bio12_precip_annual_mm", "bio13_precip_wettest_month_mm", "elevation_m")
distances <- c("distance_road_m", "distance_waterway_m", "distance_settlement_m")
fractions <- c("lc_fraction_artificial", "lc_fraction_agriculture",
               "lc_fraction_forest_seminatural", "lc_fraction_wetland", "lc_fraction_water")
climate_labels <- c("Annual mean temperature (\u00B0C)", "Temperature seasonality (SD, \u00B0C)",
                    "Wettest quarter temperature (\u00B0C)", "Annual precipitation (mm)",
                    "Wettest month precipitation (mm)", "Elevation (m)")
distance_labels <- c("Distance to road (m)", "Distance to waterway (m)", "Distance to settlement (m)")
fraction_labels <- c("Artificial surfaces", "Agricultural areas", "Forest / seminatural", "Wetlands", "Water bodies")
main_variables <- c(climate, distances, fractions)
main_labels <- setNames(c(climate_labels, distance_labels, paste0(fraction_labels, " (%)")), main_variables)
colors <- c("Background (0)" = "#6DCDF4", "Heracleum (1)" = "#78003F")
number_labels <- function(x) format(x, trim = TRUE, big.mark = ",", scientific = FALSE)
wrap_labels <- function(x, width = 30) {
  vapply(x, function(s) paste(strwrap(s, width), collapse = "\n"), character(1))
}

theme_set(theme_minimal(base_size = 13) +
            theme(legend.position = "bottom", legend.title = element_blank(),
                  panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
                  panel.spacing = grid::unit(1.4, "lines"),
                  strip.text = element_text(face = "bold", size = 13),
                  plot.title = element_text(face = "bold", size = 19, hjust = .5),
                  plot.title.position = "plot",
                  plot.subtitle = element_text(size = 12, hjust = .5, margin = margin(b = 14)),
                  plot.margin = margin(15, 20, 15, 20)))

long_table <- function(variables, labels) {
  d <- do.call(rbind, lapply(seq_along(variables), function(i) {
    data.frame(group = data$group, variable = labels[i], value = data[[variables[i]]])
  }))
  d$variable <- factor(d$variable, levels = labels)
  d
}

climate_long <- long_table(climate, climate_labels)
climate_long$value[climate_long$variable == climate_labels[2]] <-
  climate_long$value[climate_long$variable == climate_labels[2]] / 100

climate_panels <- function(type) {
  panels <- lapply(climate_labels, function(label) {
    d <- climate_long[climate_long$variable == label, ]
    p <- ggplot(d, aes(value, fill = group))
    if (type == "box") {
      p <- p + aes(y = group) +
        geom_boxplot(width = .5, outlier.alpha = .12, outlier.size = .65, orientation = "y") +
        theme(legend.position = "none")
    } else {
      p <- p + aes(color = group) + geom_density(alpha = .14, linewidth = .8) +
        scale_color_manual(values = colors)
    }
    p + scale_fill_manual(values = colors) +
      scale_x_continuous(labels = number_labels, n.breaks = 4) +
      labs(title = wrap_labels(label, 28), x = NULL, y = if (type == "box") NULL else "Density") +
      theme(plot.title = element_text(size = 12, hjust = .5))
  })
  wrap_plots(panels, ncol = 3, nrow = 2, guides = "collect") +
    plot_annotation(
      title = if (type == "box") "Climate and elevation" else "Climate distributions and overlap",
      theme = theme(plot.title = element_text(hjust = .5, face = "bold", size = 19))) &
    theme(legend.position = if (type == "box") "none" else "bottom")
}

plots <- list(climate = climate_panels("box"), climate_densities = climate_panels("density"))

cor_labels <- c("Annual temp.\n(\u00B0C)", "Temp. SD\n(\u00B0C)", "Wet quarter T\n(\u00B0C)",
                "Annual precip.\n(mm)", "Wet month precip.\n(mm)", "Elevation\n(m)",
                "Road distance\n(m)", "Waterway distance\n(m)", "Settlement distance\n(m)",
                "Artificial\n(%)", "Agriculture\n(%)", "Forest\n(%)", "Wetland\n(%)", "Water\n(%)")
correlation <- cor(data[main_variables], method = "spearman", use = "pairwise.complete.obs")
dimnames(correlation) <- list(cor_labels, cor_labels)
correlation_table <- as.data.frame(as.table(correlation))
correlation_table$label <- sprintf("%.2f", ifelse(abs(correlation_table$Freq) < .005, 0, correlation_table$Freq))

plots$correlations <- ggplot(correlation_table, aes(Var1, Var2, fill = Freq)) +
  geom_tile(color = "white") +
  geom_text(aes(label = label, color = Freq > .65), size = 2.8) +
  scale_color_manual(values = c("FALSE" = "black", "TRUE" = "white"), guide = "none") +
  scale_fill_gradient2(low = "#6DCDF4", mid = "white", high = "#78003F",
                       limits = c(-1, 1), name = "Spearman \u03C1") +
  scale_y_discrete(limits = rev(cor_labels)) + coord_equal() +
  guides(fill = guide_colorbar(barwidth = grid::unit(7, "cm"), title.position = "top")) +
  labs(title = "Correlations among main predictors", x = NULL, y = NULL) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
        axis.text.y = element_text(size = 9), panel.grid = element_blank(),
        legend.title = element_text(size = 11))

counts <- as.data.frame(table(group = data$group))
counts$label <- paste0(number_labels(counts$Freq), " cells (", round(100 * counts$Freq / nrow(data)), "%)")
plots$counts <- ggplot(counts, aes(group, Freq, fill = group)) +
  geom_col(width = .5) + geom_text(aes(label = label), vjust = -.6, size = 5) +
  scale_fill_manual(values = colors) +
  scale_y_continuous(labels = number_labels, expand = expansion(mult = c(0, .15))) +
  labs(title = "Cells in the analysis", x = NULL, y = "Number of cells") +
  theme(legend.position = "none")

monthly <- grep("^(tavg|tmin|tmax|prec)_[0-9]{2}$", names(data), value = TRUE)
effect_table <- do.call(rbind, lapply(c(main_variables, monthly), function(variable) {
  x0 <- data[data$y == 0, variable]
  x1 <- data[data$y == 1, variable]
  x0 <- x0[is.finite(x0)]
  x1 <- x1[is.finite(x1)]
  pooled_sd <- sqrt(((length(x0) - 1) * var(x0) + (length(x1) - 1) * var(x1)) /
                      (length(x0) + length(x1) - 2))
  data.frame(variable = variable, difference = (mean(x1) - mean(x0)) / pooled_sd)
}))

main_effects <- effect_table[effect_table$variable %in% main_variables, ]
main_effects$label <- unname(main_labels[main_effects$variable])
plots$differences <- ggplot(main_effects, aes(difference, reorder(label, difference))) +
  geom_vline(xintercept = 0, color = "grey50", linetype = "dashed") +
  geom_segment(aes(x = 0, xend = difference, yend = reorder(label, difference)), color = "grey75") +
  geom_point(size = 3.7, color = colors[2]) +
  scale_y_discrete(labels = function(x) wrap_labels(x, 33)) +
  scale_x_continuous(expand = expansion(mult = .12)) +
  labs(title = "How the main predictors differ",
       subtitle = "Left of zero: lower at Heracleum sites | Right of zero: higher at Heracleum sites",
       x = "Standardized mean difference (SD)", y = NULL)

distance_long <- long_table(distances, distance_labels)
plots$distances <- ggplot(distance_long, aes(value, group, fill = group)) +
  geom_boxplot(width = .5, outlier.alpha = .12, outlier.size = .65, orientation = "y") +
  facet_wrap(~variable, scales = "free_x", ncol = 1) +
  scale_fill_manual(values = colors) +
  scale_x_continuous(trans = scales::pseudo_log_trans(sigma = 50), limits = c(0, NA),
                     breaks = c(0, 50, 100, 250, 500, 1000, 2500, 5000, 10000), labels = number_labels) +
  labs(title = "Distances to landscape features", x = "Distance (m)", y = NULL) +
  theme(legend.position = "none")

fraction_long <- long_table(fractions, fraction_labels)
fraction_long$value <- fraction_long$value * 100
cover_means <- aggregate(value ~ variable + group, fraction_long, mean)
plots$fractions <- ggplot(cover_means, aes(value, variable, fill = group)) +
  geom_col(position = position_dodge(.75), width = .65) +
  geom_text(aes(label = sprintf("%.1f%%", value)), position = position_dodge(.75),
            hjust = -.15, size = 4) +
  scale_fill_manual(values = colors) + scale_y_discrete(limits = rev(fraction_labels)) +
  scale_x_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
  labs(title = "Average land cover within a cell", x = "Mean area share (%)", y = NULL)

monthly_effects <- effect_table[effect_table$variable %in% monthly, ]
monthly_effects$month <- as.integer(sub(".*_", "", monthly_effects$variable))
monthly_effects$type <- factor(sub("_.*", "", monthly_effects$variable),
                               levels = c("prec", "tmax", "tmin", "tavg"),
                               labels = c("Precipitation", "Maximum temperature", "Minimum temperature", "Mean temperature"))
effect_limit <- max(abs(monthly_effects$difference))
monthly_effects$label <- sprintf("%+.2f", ifelse(abs(monthly_effects$difference) < .005, 0, monthly_effects$difference))

plots$monthly_differences <- ggplot(monthly_effects, aes(month, type, fill = difference)) +
  geom_tile(color = "white", linewidth = 1) +
  geom_text(aes(label = label, color = difference > .65 * effect_limit), size = 4) +
  scale_color_manual(values = c("FALSE" = "black", "TRUE" = "white"), guide = "none") +
  scale_fill_gradient2(low = "#6DCDF4", mid = "white", high = "#78003F",
                       limits = c(-effect_limit, effect_limit), name = "Standardized difference (SD)") +
  scale_x_continuous(breaks = 1:12, labels = month.abb, expand = c(0, 0)) +
  guides(fill = guide_colorbar(barwidth = grid::unit(9, "cm"), title.position = "top")) +
  labs(title = "When do the groups differ most?",
       subtitle = "Negative: lower mean at Heracleum sites | Positive: higher mean at Heracleum sites",
       x = NULL, y = NULL) +
  theme(panel.grid = element_blank(), legend.title = element_text(size = 11))

sizes <- list(climate = c(16, 9), climate_densities = c(16, 9), correlations = c(14, 12),
              counts = c(9, 6), differences = c(13, 10), distances = c(12, 10),
              fractions = c(12, 7), monthly_differences = c(15, 6))

for (name in names(plots)) {
  ggsave(file.path(output_dir, paste0(name, ".png")), plots[[name]], device = grDevices::png,
         width = sizes[[name]][1], height = sizes[[name]][2], units = "in", dpi = 300, bg = "white")
}

message("Saved ", length(plots), " PNG files directly to: ", output_dir)
if (interactive()) for (p in plots) print(p)
