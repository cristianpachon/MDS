library(tidyverse)
library(ggplot2)

# Load data ----
data_path = file.path(getwd(), 'data')
load(file.path(data_path, "df_scenarios_full.RData"))
load(file.path(data_path, "df_eigenvalues_full.RData"))
load(file.path(data_path, "df_conversion.RData"))
load(file.path(data_path, "df_mds_paramenters_full.RData"))

# Manipulate data ----
scenario_identifier = c("sample_size", "n_cols", "n_main_dimensions", "var_main")

# Join scenarios and eigenvalues
scenarios_with_main_dimensions = df_scenarios_full %>% 
  left_join(df_mds_paramenters_full, by = c("id" = "scenario_id")) %>% 
  filter(n_main_dimensions > 0,  !is.na(processed_at), experiment_label %in% c("l_experiment"))

total_scenarios = nrow(scenarios_with_main_dimensions)

df_join_scenarios_eigenvalues = scenarios_with_main_dimensions %>% 
  select_at(c("id", scenario_identifier, "var", "experiment_label"))   %>% 
  left_join(
    df_eigenvalues_full,
    by = c("id" = "scenario_id")) 

# Build data frames that contain eigenvalues and var
i = 1
while (i <= total_scenarios) {
  current_scenario = scenarios_with_main_dimensions[i, ]
  scenario_id = current_scenario$id
  eigen_data = df_join_scenarios_eigenvalues[df_join_scenarios_eigenvalues$id == scenario_id, ]
  n_main_dimension_scenario = current_scenario$n_main_dimensions
  
  var_sim = map2(.x = eigen_data$var, .y = eigen_data$n_main_dimensions, .f = ~ .x[1:.y]) %>% unlist() %>% 
    matrix(., nrow = length(eigen_data$var), byrow = TRUE) %>% as.data.frame() %>% 
    set_names(nm = paste0("dim_", sprintf("%02d", 1:n_main_dimension_scenario)))
  
  var_sim$scenario_id = scenario_id
  var_sim$num_sim = eigen_data$num_sim
  var_sim$method_name = eigen_data$method_name
  
  eigenvalues_sim = map2(.x = eigen_data$eigenvalue_vector, .y = eigen_data$n_main_dimensions, .f = ~ .x[1:.y]) %>% 
    unlist() %>% matrix(., nrow = length(eigen_data$var), byrow = TRUE) %>% as.data.frame() %>%
    set_names(nm = paste0("dim_", sprintf("%02d", 1:n_main_dimension_scenario)))
  
  eigenvalues_sim$scenario_id = scenario_id
  eigenvalues_sim$num_sim = eigen_data$num_sim
  eigenvalues_sim$method_name = eigen_data$method_name
  
  if (i == 1) {
    df_var_flat = var_sim
    df_eigenvalues_flat = eigenvalues_sim
  } else {
    df_var_flat = plyr::rbind.fill(df_var_flat, var_sim)
    df_eigenvalues_flat = plyr::rbind.fill(df_eigenvalues_flat, eigenvalues_sim)
  }
  
  i = i + 1
}

df_var_flat_long = df_var_flat %>% 
  pivot_longer(cols = starts_with("dim"), names_to = "dim", values_to = "var") %>% 
  filter(!is.na(var))
 
df_eigenvalues_long = df_eigenvalues_flat %>% 
  pivot_longer(cols = starts_with("dim"), names_to = "dim", values_to = "eigenvalue") %>% 
  filter(!is.na(eigenvalue))

# Enrich scenarios with eigenvalue information
eigenvalues_information = df_join_scenarios_eigenvalues %>% 
  select_at(c("id", scenario_identifier, "num_sim", "method_name", "experiment_label")) %>% 
  left_join(df_var_flat_long, by = c("id" = "scenario_id", "num_sim" = "num_sim", "method_name" = "method_name")) %>% 
  left_join(df_eigenvalues_long, by = c("id" = "scenario_id", "num_sim" = "num_sim", "method_name" = "method_name", "dim" = "dim")) %>% 
  left_join(df_conversion) %>% 
  left_join(df_mds_paramenters_full, by = c("id" = "scenario_id")) %>% 
  mutate(error = eigenvalue - var)


# Analyse data  ----
# Bias
eigenvalues_information %>%
  group_by(sample_size, algorithm, dim) %>%
  summarise(bias = mean(error)) %>% 
  mutate(sample_size = as.factor(sample_size)) %>% 
  ggplot(aes(x = sample_size, y = bias, group = algorithm, color = algorithm)) +
  geom_point() +
  geom_hline(yintercept = 0, linetype = "dashed") +
  facet_wrap( ~ dim, ncol = 2) +
  theme(panel.spacing.y=unit(0.5, "lines"), legend.position="bottom") +
  scale_color_manual(values = c("#0000FF", "#FF0000", "#00AF91")) + 
  xlab("Sample Size") + 
  ylab("Bias") +
  ggsave(file.path(getwd(), "images", "bias_all.png"),
         dpi = 300, dev = 'png', height = 18, width = 22, units = "cm")
 
# MSE
eigenvalues_information %>% 
  group_by(sample_size, algorithm, dim) %>% 
  summarise(
    mse = mean(error^2),
    rmse = sqrt(mse)
  ) %>% 
  mutate(sample_size = as.factor(sample_size)) %>% 
  ggplot(aes(x = sample_size, y = mse, group = algorithm, color = algorithm)) +
  geom_point() +
  facet_wrap( ~ dim, ncol = 2) +
  theme(panel.spacing.y=unit(0.5, "lines"), legend.position="bottom") +
  scale_color_manual(values = c("#0000FF", "#FF0000", "#00AF91")) + 
  xlab("Sample Size") + 
  ylab("MSE") +
  ggsave(file.path(getwd(), "images", "mse_all.png"),
         dpi = 300, dev = 'png', height = 18, width = 22, units = "cm")

# Error for a particular scenario
eigenvalues_information %>% 
  filter(sample_size == 10^6, n_main_dimensions == 10, n_cols == 100) %>% 
  ggplot(aes(x = algorithm, y = error, fill = algorithm)) +
  geom_boxplot() + 
  facet_wrap( ~ dim, ncol = 5) +
  theme(
    panel.spacing.y=unit(0.5, "lines"), 
    axis.title.x=element_blank(),
    axis.text.x=element_blank(),
    axis.ticks.x=element_blank(),
    legend.position="bottom"
  ) +
  scale_fill_manual(values = c("#0000FF", "#FF0000", "#00AF91")) + 
  ylab("Error") +
  geom_hline(yintercept = 0, linetype = "dashed") +
  ggsave(file.path(getwd(), "images", "error_1000000_100_10.png"),
         dpi = 300, dev = 'png', height = 18, width = 22, units = "cm")
