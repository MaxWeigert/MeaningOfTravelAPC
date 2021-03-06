### This is the main code file containing the analyses done for the
### publication "Temporal Changes in Travel Behavior over Age, Period and
### Cohort - An Explanation Through the Meaning of Travel".

# Loading of necessary packages and sourcing of self-defined functions:
library(APCtools)
library(dplyr)
library(ggplot2)
library(ggpubr)
library(mgcv)
library(pROC)
source("Code/Functions.R")
theme_set(theme_minimal())


################################################################################

# Description of response variables:

# define age and period groups for the density matrices
age_groups    <- list(c(70,79),c(60,69),c(50,59),c(40,49),c(30,39),c(20,29),c(14,19))
period_groups <- list(c(1970,1979),c(1980,1989),c(1990,1999),c(2000,2009),c(2010,2018))

# participation plot
dat_P <- read_and_prepare_data(model = "participation")

# create the participation variable
dat_P <- dat_P %>% 
  mutate(participation = case_when(JS_Anzahl_URs == 0 ~ "0 trips",
                                   TRUE               ~ ">= 1 trips")) %>% 
  mutate(participation = factor(participation, levels = c("0 trips",">= 1 trips")))

# marginal distribution
gg1 <- plot_variable(dat_P, "participation", legend_title = "Participation") +
    scale_fill_manual("Participation", values = c("lightblue","dodgerblue3"))

# density matrix
plot_densityMatrix(dat_P, y_var = "participation",
                   age_groups = age_groups, period_groups = period_groups)

# travel frequency plot
dat_F <- read_and_prepare_data(model = "frequency")

dat_F <- dat_F %>% 
  filter(JS_Anzahl_URs > 0) %>% 
  mutate(JS_Anzahl_URs_cat = case_when(JS_Anzahl_URs < 5 ~ as.character(JS_Anzahl_URs),
                                       TRUE              ~ "5+ trips")) %>% 
  mutate(JS_Anzahl_URs_cat = factor(JS_Anzahl_URs_cat, levels = c("5+ trips","4","3","2","1")))

# marginal distribution
green_colors <- RColorBrewer::brewer.pal(6, "Greens")[6:2]
gg2 <- plot_variable(dat_F, "JS_Anzahl_URs_cat") +
    scale_fill_manual("Number of\ntrips", values = green_colors)

# density matrix
plot_densityMatrix(dat_F, y_var = "JS_Anzahl_URs_cat",
                   age_groups = age_groups, period_groups = period_groups)

# relative travel expenses plot 
dat_E <- read_and_prepare_data(model = "expenses")

# first plot the household income
gg3 <- plot_variable(dat_E, y_var = "S_Einkommen_HH_equi", plot_type = "line-points",
                     ylim = c(0,1900), ylab = "Median of household income [€]")

# plot the relative expenses
gg4 <- plot_variable(dat_E, y_var = "rel_expenses", plot_type = "line-points",
                     ylab = "Median of rel. expenses [€]", ylim = c(0,1))

# joint plot
ggpubr::ggarrange(gg1, gg2, gg3, gg4, ncol = 2, nrow = 2)
ggsave("Graphics/Figure2.jpeg", width = 10, height = 6, dpi = 300,
       bg = "white")


################################################################################

# Description of covariates:

# data prep
dat <- read_and_prepare_data(model = "participation")

dat <- dat %>% 
  dplyr::rename(Gender                 = S_Geschlecht,
                Household_net_income   = S_Einkommen_HH,
                Education_level        = S_Bildung,
                Household_size         = S_Haushaltsgroesse,
                Children_under_5_years = S_Kinder_0_bis_5_binaer,
                Size_of_residence      = S_Wohnortgroesse,
                Duration_of_main_trip  = JS_HUR_Reisedauer)

# categorize the household net income
dat <- dat %>% 
  mutate(Household_net_income_cat = case_when(Household_net_income < 1000 ~ "[0,1000)",
                                              Household_net_income < 2000 ~ "[1000,2000)",
                                              Household_net_income < 3000 ~ "[2000,3000)",
                                              Household_net_income < 4000 ~ "[3000,4000)",
                                              Household_net_income < 5000 ~ "[4000,5000)",
                                              Household_net_income < 6000 ~ "[5000,6000)",
                                              TRUE                        ~ ">= 6000"))

# descriptions ------------------------------------------------------------
vars <- c("Gender","Household_net_income_cat","Education_level","Household_size",
          "Children_under_5_years","Size_of_residence","Duration_of_main_trip")

# Note: Among the above variables only the trip duration has some NA values,
#       and these are only in the data for non-travelers.´
#       Accordingly, we don't have to bother with NA values in the following
#       table.

# create the frequency table with separate information for all travelers
freq_dat_list <- lapply(vars, function(var) {
  
  x_all       <- dat[[var]]
  x_travelers <- dat[[var]][dat$y_atLeastOneUR == 1]
  
  tab_abs_all       <- table(x_all)
  tab_abs_travelers <- table(x_travelers)
  tab_rel_all       <- prop.table(tab_abs_all)
  tab_rel_travelers <- prop.table(tab_abs_travelers)
  
  freq_dat <- data.frame(Variable       = var,
                         Value          = names(tab_abs_all),
                         n_overall      = as.vector(tab_abs_all),
                         n_travelers    = as.vector(tab_abs_travelers),
                         freq_overall   = paste0(round(100 * as.vector(tab_rel_all),       1), "%"),
                         freq_travelers = paste0(round(100 * as.vector(tab_rel_travelers), 1), "%"))
  
  # only keep the information on the trip duration for travelers
  if (var == "Duration_of_main_trip") {
    freq_dat$n_overall <- freq_dat$freq_overall <- NA
  }
  
  return(freq_dat)
})

freq_dat <- dplyr::bind_rows(freq_dat_list)
write.csv2(freq_dat, file = "Graphics/Table1.csv", row.names = FALSE)


# table of generations
gen_table <- dat %>% 
  group_by(generation) %>% 
  summarize(birth_years   = paste0(min(cohort)," - ",max(cohort)),
            rel_frequency = paste0(round(100 * n() / nrow(dat), 1), "%"),
            obs_periods   = paste0(min(period)," - ",max(period)),
            obs_ages      = paste0(min(age)," - ",max(age)))

write.csv2(gen_table, file = "Graphics/TableA1.csv", row.names = FALSE)


################################################################################

# Model effects:

# model estimation participation
dat_P <- read_and_prepare_data(model = "participation")

model_P <- bam(formula = y_atLeastOneUR ~ te(period, age, k = c(10, 10), bs = "ps") +
                 S_Geschlecht + S_Kinder_0_bis_5_binaer + S_Wohnortgroesse +
                 S_Bildung + s(S_Einkommen_HH_equi, bs = "ps", k =10) +
                 S_Haushaltsgroesse,
               family = binomial(link = "logit"), data = dat_P)
saveRDS(object = model_P, file = "Models/Main_Analysis/Model_participation.rds")

# model estimation frequency
dat_F <- read_and_prepare_data(model = "frequency")

model_F <- bam(y_atLeastTwoURs ~ te(period, age, k = c(10, 10), bs = "ps") +
                 S_Geschlecht + S_Kinder_0_bis_5_binaer + S_Wohnortgroesse + S_Bildung +
                 s(S_Einkommen_HH_equi, bs = "ps", k = 10) + S_Haushaltsgroesse,
               family = binomial(link = "logit"), data = dat_F)
saveRDS(object = model_F, file = "Models/Main_Analysis/Model_frequency.rds")

# model estimation expenses 
dat_E <- read_and_prepare_data(model = "expenses")

model_E <- bam(formula = rel_expenses ~ te(period, age, bs = "ps", k = c(10, 10)) +
                 S_Geschlecht + S_Kinder_0_bis_5_binaer + S_Wohnortgroesse +
                 S_Bildung + S_Haushaltsgroesse + JS_HUR_Reisedauer +
                 s(S_Einkommen_HH_equi, bs = "ps", k = 10),
               family = Gamma(link = "log"),
               data = dat_E)
saveRDS(object = model_E, file = "Models/Main_Analysis/Model_expenses.rds")

# general preparations for all following plots 
model_suffices <- c("P","F","E")
model_labels   <- c("Participation","Frequency","Rel. Expenses")

# data prep for the marginal effect plots 
plot_dat_list <- lapply(model_suffices, function(suffix) {
  
  # return a list for all age, period and cohort
  model_dat_list <- plot_marginalAPCeffects(model           = get(paste0("model_",suffix)),
                                            dat             = get(paste0("dat_",suffix)),
                                            variable        = "age",
                                            return_plotData = TRUE)
  
  model_dat <- model_dat_list[2:4] %>% dplyr::bind_rows() %>% 
    mutate(model = suffix)
  
  return(model_dat)
})

plot_dat <- plot_dat_list %>% dplyr::bind_rows() %>% 
  mutate(model    = factor(model,    levels = model_suffices, labels = model_labels),
         variable = factor(variable, levels = c("Age","Period","Cohort")))

# marginal effect plots 
vlines_cohort <- list("cohort" = c(1938.5,1946.5,1966.5,1982.5,1994.5))
cols          <- rev(scales::hue_pal()(3))

# vertical lines, only to be drawn for the cohort plots
vline_dat <- data.frame(variable = factor("Cohort", levels = c("Age","Period","Cohort")),
                        x        = c(1938.5,1946.5,1966.5,1982.5,1994.5))

# 1) plot grid for participation and frequency
gg1 <- plot_dat %>% 
  filter(model %in% c("Participation","Frequency")) %>% 
  ggplot(aes(x = value, y = effect, col = model)) +
  geom_hline(yintercept = 1, lty = 2, col = gray(0.3)) +
  geom_vline(data = vline_dat, aes(xintercept = x), lty = 2, col = gray(0.3)) +
  geom_line() +
  facet_grid(model ~ variable, scales = "free") +
  scale_y_continuous("Odds Ratio", breaks = c(.25,.5,1,2), trans = "log2",
                     limits = range(plot_dat$effect)) +
  scale_color_manual(values = cols[1:2]) +
  theme(axis.title.x     = element_blank(),
        axis.text.x      = element_blank(),
        strip.background = element_rect(fill = gray(0.8)),
        legend.position  = "none")

# 2) plot grid for expenses
gg2 <- plot_dat %>% 
  filter(model == "Rel. Expenses") %>% 
  ggplot(aes(x = value, y = effect, col = model)) +
  geom_hline(yintercept = 1, lty = 2, col = gray(0.3)) +
  geom_vline(data = vline_dat, aes(xintercept = x), lty = 2, col = gray(0.3)) +
  geom_line() +
  facet_grid(model ~ variable, scales = "free") +
  scale_y_continuous("exp(Effect)", breaks = c(0.9,1,1.1), trans = "log2") +
  scale_color_manual(values = cols[3]) +
  theme(axis.title.x     = element_blank(),
        strip.text.x     = element_blank(),
        strip.background = element_rect(fill = gray(0.8)),
        legend.position  = "none")

ggpubr::ggarrange(gg1, gg2, nrow = 2, heights = c(2/3,1/3))
ggsave("Graphics/Figure3.jpeg", width = 6, height = 4, dpi = 300,
       bg = "white")

create_APCsummary(list(model_P), dat = dat_P, apc_range = list("cohort" = 1939:2018))
create_APCsummary(list(model_F), dat = dat_F, apc_range = list("cohort" = 1939:2018))
create_APCsummary(list(model_E), dat = dat_E, apc_range = list("cohort" = 1939:2018))

# linear covariate effects
plot_dat_list <- lapply(model_suffices, function(suffix) {
  
  m <- get(paste0("model_",suffix))
  plot_dat_m <- plot_linearEffects(m, return_plotData = TRUE) %>% 
    mutate(model = model_labels[match(suffix, model_suffices)])
  
  return(plot_dat_m)
})

plot_dat <- dplyr::bind_rows(plot_dat_list) %>%
  mutate(model = factor(x = model,
                        levels = c("Participation", "Frequency",
                                   "Rel. Expenses"))) %>% 
  mutate(vargroup = as.character(vargroup)) %>% 
  mutate(vargroup = case_when(vargroup == "S_Geschlecht"            ~ "Gender",
                              vargroup == "S_Bildung"               ~ "Education",
                              vargroup == "S_Kinder_0_bis_5_binaer" ~ "Young children",
                              vargroup == "S_Haushaltsgroesse"      ~ "Household size",
                              vargroup == "JS_HUR_Reisedauer"       ~ "Trip length",
                              vargroup == "S_Wohnortgroesse"        ~ "City size",
                              TRUE ~ vargroup)) %>% 
  mutate(vargroup = factor(vargroup, levels = c("Gender","Education","Household size",
                                                "Young children","City size","Trip length"))) %>% 
  mutate(param = as.character(param)) %>% 
  mutate(param = case_when(param == "weiblich"                  ~ "female",
                           grepl("Mittlere Reife", param)       ~ "secondary school",
                           grepl("Abitur",         param)       ~ "high school",
                           grepl("Universitaet",   param)       ~ "university or college",
                           param == "Kinder dieser Altersstufe" ~ "yes",
                           param == "5.3"                       ~ ">=5",
                           param == "5.000 bis 49.999"          ~ "[5,000; 50,000)",
                           param == "50.000 bis 99.999"         ~ "[50,000; 100,000)",
                           param == "100.000 bis 499.999"       ~ "[100,000; 500,000)",
                           param == "500.000 und mehr"          ~ ">=500,000",
                           param == "6 bis 8 Tage"              ~ "6-8 days",
                           param == "9 bis 12 Tage"             ~ "9-12 days",
                           param == "13 bis 15 Tage"            ~ "13-15 days",
                           param == "16 bis 19 Tage"            ~ "16-19 days",
                           param == "20 bis 22 Tage"            ~ "20-22 days",
                           param == "23 bis 26 Tage"            ~ "23-26 days",
                           param == "27 bis 29 Tage"            ~ "27-29 days",
                           param == "30 Tage und mehr"          ~ ">=30 days",
                           TRUE ~ param)) %>% 
  mutate(param = factor(param, levels = c("female","secondary school","high school","university or college",
                                          "2","3","4",">=5","yes",
                                          "[5,000; 50,000)","[50,000; 100,000)",
                                          "[100,000; 500,000)",">=500,000",
                                          "6-8 days","9-12 days","13-15 days",
                                          "16-19 days","20-22 days","23-26 days",
                                          "27-29 days",">=30 days")))

ggplot(plot_dat, mapping = aes(x = param, y = coef)) +
  geom_hline(yintercept = 1, col = gray(0.3), lty = 2) +
  geom_pointrange(mapping = aes(ymin = CI_lower, ymax = CI_upper, col = vargroup), size = 1) +
  geom_point(mapping = aes(col = vargroup), size = 1) +
  scale_y_continuous(trans = "log2", name = "exp(Effect)") +
  colorspace::scale_colour_discrete_qualitative(palette = "Dark 3") +
  facet_grid(model ~ vargroup, scales = "free_x") +
  theme(legend.position = "none",
        axis.title.x    = element_blank(),
        axis.text.x     = element_text(angle = 45, hjust = 1),
        strip.background = element_rect(fill = gray(0.8)))
ggsave("Graphics/FigureB1.jpeg", width = 8, height = 7, dpi = 300,
       bg = "white")

# nonlinear income effects 
plot_dat_list <- lapply(model_suffices, function(suffix) {
  
  m <- get(paste0("model_",suffix))
  plot_dat_m <- plot_1Dsmooth(m, select = 2, return_plotData = TRUE) %>% 
    mutate(model = model_labels[match(suffix, model_suffices)])
  
  return(plot_dat_m)
})

plot_dat <- dplyr::bind_rows(plot_dat_list) %>%
  mutate(model = factor(x = model,
                        levels = c("Participation", "Frequency",
                                   "Rel. Expenses")))

# trim the CIs to limit the y-axis
ylim <- c(0.25, 16)
plot_dat$CI_lower[plot_dat$CI_lower < ylim[1]] <- ylim[1]
plot_dat$CI_upper[plot_dat$CI_upper > ylim[2]] <- ylim[2]

ggplot() +
  geom_hline(yintercept = 1, lty = 2, col = gray(0.3)) +
  geom_ribbon(data = plot_dat, aes(x, ymin = CI_lower, ymax = CI_upper),
              fill = gray(0.75)) + 
  geom_line(data = plot_dat, aes(x, y, col = model)) +
  facet_grid(. ~ model) + scale_x_continuous(limits = c(0, 6000)) +
  scale_y_continuous("exp(Effect)", trans = "log2", limits = c(0.25, 16),
                     breaks = 2^c(-2,-1,0,1, 2, 3, 4),
                     labels = c("0.25","0.5","1","2", "4", "8", "16")) +
  scale_color_manual(values = cols) +
  xlab("Household income [€]") +
  theme(strip.background = element_rect(fill = gray(0.8)),
        legend.position  = "none",
        panel.grid.minor = element_blank())
ggsave("Graphics/FigureB2.jpeg", width = 6, height = 2, dpi = 300,
       bg = "white")


################################################################################

# Model evaluation:

# Participation:
set.seed(3456)
train_index <- sample(1:nrow(dat_P), 0.8 * nrow(dat_P))
dat_P_train <- dat_P[train_index, ]
dat_P_test <- dat_P[-train_index, ]
model_P_auc <- bam(formula = y_atLeastOneUR ~ te(period, age, k = c(10, 10), bs = "ps") +
                     S_Geschlecht + S_Kinder_0_bis_5_binaer + S_Wohnortgroesse +
                     S_Bildung + s(S_Einkommen_HH_equi, bs = "ps", k =10) +
                     S_Haushaltsgroesse,
                   family = binomial(link = "logit"), data = dat_P_train)
prediction <- predict(object = model_P_auc, newdata = dat_P_test)
roc(dat_P_test$y_atLeastOneUR, prediction)$auc

# Frequency:
set.seed(3456)
train_index <- sample(1:nrow(dat_F), 0.8 * nrow(dat_F))
dat_F_train <- dat_F[train_index, ]
dat_F_test <- dat_F[-train_index, ]
model_F_auc <- bam(formula = y_atLeastTwoURs ~ te(period, age, k = c(10, 10), bs = "ps") +
                     S_Geschlecht + S_Kinder_0_bis_5_binaer + S_Wohnortgroesse +
                     S_Bildung + s(S_Einkommen_HH_equi, bs = "ps", k =10) +
                     S_Haushaltsgroesse,
                   family = binomial(link = "logit"), data = dat_F_train)
prediction <- predict(object = model_F_auc, newdata = dat_F_test)
roc(dat_F_test$y_atLeastTwoURs, prediction)$auc

# Expenses:
set.seed(3456)
train_index <- sample(1:nrow(dat_E), 0.8 * nrow(dat_E))
dat_E_train <- dat_E[train_index, ]
dat_E_test <- dat_E[-train_index, ]
model_E_train <- bam(formula = rel_expenses ~ te(period, age, bs = "ps", k = c(10, 10)) +
                       S_Geschlecht + S_Kinder_0_bis_5_binaer + S_Wohnortgroesse +
                       S_Bildung + S_Haushaltsgroesse + JS_HUR_Reisedauer +
                       s(S_Einkommen_HH_equi, bs = "ps", k = 10),
                     family = Gamma(link = "log"),
                     data = dat_E_train)
prediction <- predict(object = model_E_train, newdata = dat_E_test, 
                      type = "response")
mean(abs(prediction - dat_E_test$rel_expenses), na.rm = TRUE)
median(abs(prediction - dat_E_test$rel_expenses) / dat_E_test$rel_expenses,
       na.rm = TRUE)

# QQ plot for the expenses model
jpeg("Graphics/FigureB3.jpeg", width = 7, height = 7, units = "cm",
    pointsize = 5, res = 300, bg = "white")
qq.gam(model_E)
dev.off()


################################################################################

















