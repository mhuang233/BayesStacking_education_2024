### :::::: Real Data Analysis :::::: ###
{
  library(loo)
  library(rstanarm)
  library(rstan)
  library(LaplacesDemon)
  library(kableExtra)
  library(bayesplot)
  options(mc.cores = parallel::detectCores())
}
set.seed(53705)
# data
df0 <- read.csv("pisa2018.BayesBook.csv")

df <- df0 %>%
  dplyr::select(SchoolID, CNTSTUID, Female, ESCS, METASUM, PERFEED, HOMEPOS, 
                ADAPTIVITY, TEACHINT, ICTRES, ATTLNACT, COMPETE, JOYREAD,
                WORKMAST, GFOFAIL, SWBP, MASTGOAL, BELONG, SCREADCOMP, 
                PISADIFF, Public, PV1READ, SCREADDIFF)


# subset
sch <- table(df$SchoolID)
dt0  <- subset(df, SchoolID %in% names(sch[sch > 10]))

# check
library(tidyverse)

dt0 %>%
  group_by(SchoolID)%>%
  summarise(n=n()) # 148 in total

#===============================#
### ::: For reduced sample::: ###
#===============================#

# randomly select 10 students in each group
dt <- dt0 %>% group_by(SchoolID) %>% slice_sample(n = 10)
SchID <- dt$SchoolID 
unique_sch <- unique(dt$SchoolID)

sch_sample <- sample(unique_sch, 50)
sch_index <- which(SchID %in% sch_sample)

df <- dt[sch_index, ]

# model fitting
bsm <- list()
loo_bs <- list()

bsm[[1]] <- stan_lmer(
  PV1READ ~ Female + ESCS + HOMEPOS + ICTRES + (1 + ICTRES|SchoolID), data = df, 
  prior_intercept = student_t(3, 470, 100),
  iter = iter, chains = 4,
  adapt_delta=.999,thin=10)

bsm[[2]] <- stan_lmer(
  PV1READ ~ JOYREAD + PISADIFF + SCREADCOMP + SCREADDIFF + (1|SchoolID),
  data = df, prior_intercept = student_t(3, 470, 100),iter = iter, chains = 4,
  adapt_delta=.999,thin=10)

bsm[[3]] <- stan_lmer(
  PV1READ ~ METASUM + GFOFAIL + MASTGOAL + SWBP + WORKMAST + ADAPTIVITY + COMPETE + (1|SchoolID),
  data = df, prior_intercept = student_t(3, 470, 100),iter = iter, chains = 4,
  adapt_delta=.999,thin=10)

bsm[[4]] <- stan_lmer(
  PV1READ ~ PERFEED + TEACHINT + BELONG + (1 + TEACHINT|SchoolID),
  data = df, prior_intercept = student_t(3, 470, 100),iter = iter, chains = 4,
  adapt_delta=.999,thin=10)

# loo and weights
loo_bs[[1]] <- loo(log_lik(bsm[[1]]))
loo_bs[[2]] <- loo(log_lik(bsm[[2]]))
loo_bs[[3]] <- loo(log_lik(bsm[[3]]))
loo_bs[[4]] <- loo(log_lik(bsm[[4]]))

system.time(w_bs <- loo_model_weights(loo_bs, method = "stacking"))
system.time(w_pbma <- loo_model_weights(loo_bs, method = "pseudobma", BB=FALSE))
system.time(w_pbmabb <- loo_model_weights(loo_bs, method = "pseudobma"))


# Obtain the LPD
lpd_point <- as.matrix(cbind(loo_bs[[1]]$pointwise[, "elpd_loo"],
                             loo_bs[[2]]$pointwise[, "elpd_loo"],
                             loo_bs[[3]]$pointwise[, "elpd_loo"],
                             loo_bs[[4]]$pointwise[, "elpd_loo"]))


# kld
# bs
n_draws <- nrow(as.matrix(bsm[[1]]));print(n_draws)
ypred_bs <- matrix(NA, nrow = n_draws, ncol = nobs(bsm[[1]]))
for (d in 1:n_draws) {
  k <- sample(1:length(w_bs), size = 1, prob = w_bs)
  ypred_bs[d, ] <- posterior_predict(bsm[[k]], draws = 1)
}


y_bs <- colMeans(ypred_bs)
d1 <- density(y_bs, kernel = c("gaussian"))$y
d0 <- density(df$PV1READ, kernel = c("gaussian"))$y
kld1 <- KLD(d1, d0)$sum.KLD.py.px

# pbma
ypred_bma <- matrix(NA, nrow = n_draws, ncol = nobs(bsm[[1]]))
for (d in 1:n_draws) {
  k <- sample(1:length(w_pbma), size = 1, prob = w_pbma)
  ypred_bma[d, ] <- posterior_predict(bsm[[k]], draws = 1)
}

y_bma <- colMeans(ypred_bma)
d2 <- density(y_bma, kernel = c("gaussian"))$y
kld2 <- KLD(d2, d0)$sum.KLD.py.px

# pbmabb
ypred_bmabb <- matrix(NA, nrow = n_draws, ncol = nobs(bsm[[1]]))
for (d in 1:n_draws) {
  k <- sample(1:length(w_pbmabb), size = 1, prob = w_pbmabb)
  ypred_bmabb[d, ] <- posterior_predict(bsm[[k]], draws = 1)
}

y_bmabb <- colMeans(ypred_bmabb)
d3 <- density(y_bmabb, kernel = c("gaussian"))$y
kld3 <- KLD(d3, d0)$sum.KLD.py.px

### ::: For BHS ::: ###
d_discrete = 1
X =  df[, c("ESCS","HOMEPOS","ICTRES",
            "JOYREAD","PISADIFF","SCREADCOMP","SCREADDIFF",
            "METASUM","GFOFAIL","MASTGOAL","SWBP","WORKMAST","ADAPTIVITY","COMPETE",
            "PERFEED","TEACHINT","BELONG")] 

stan_bhs <- list(X = X, N = nrow(X), d = ncol(X), d_discrete = d_discrete,
                 lpd_point = lpd_point, K = ncol(lpd_point), tau_mu = 1,
                 tau_sigma = 1, tau_discrete = .5, tau_con = 1)

fit_bhs<- stan("bhs_stan.stan", data = stan_bhs, chains = 4, iter = iter)

# weights
wts_bhs <- rstan::extract(fit_bhs, pars = 'w')$w
w_bhs_r <- apply(wts_bhs, c(2,3), mean)
w_bhs_m <- as.matrix(apply(wts_bhs, 3, mean))

# Obtain the KLD
ypred_bhs_r <- matrix(NA, nrow = n_draws, ncol = nobs(bsm[[1]]))
for (d in 1:n_draws) {
  k <- sample(1:4, size = 1, prob = w_bhs_m)
  ypred_bhs_r[d, ] <- posterior_predict(bsm[[k]], draws = 1)
}

y_bhs_r <- colMeans(ypred_bhs_r)

# KLD
d4 <- density(y_bhs_r, kernel = c("gaussian"))$y
kld4 <- KLD(d4, d0)$sum.KLD.py.px

# summarize the weights
wr <- data.frame(as.matrix(w_bs), as.matrix(w_pbma), as.matrix(w_pbmabb), w_bhs_m)
colnames(wr) <- c("bs","pbma", "pbmabb", "bhs")

klds <- rbind(kld1, kld2, kld3, kld4)

save(lpd_point, fit_bhs, wr, klds, bsm, loo_bs, 
     file = "real_input.RData")

#===============================#
 ### ::: For full sample ::: ###
#===============================#

df <- df0 %>%
  dplyr::select(SchoolID, CNTSTUID, Female, ESCS, METASUM, PERFEED, HOMEPOS, 
                ADAPTIVITY, TEACHINT, ICTRES, ATTLNACT, COMPETE, JOYREAD,
                WORKMAST, GFOFAIL, SWBP, MASTGOAL, BELONG, SCREADCOMP, 
                PISADIFF, Public, PV1READ, SCREADDIFF)

# model fitting
bsm <- list()
loo_bs <- list()

bsm[[1]] <- stan_lmer(
  PV1READ ~ Female + ESCS + HOMEPOS + ICTRES + (1 + ICTRES|SchoolID), data = dt, 
  prior_intercept = student_t(3, 470, 100),
  iter = iter, chains = 4,
  adapt_delta=.999,thin=10)

bsm[[2]] <- stan_lmer(
  PV1READ ~ JOYREAD + PISADIFF + SCREADCOMP + SCREADDIFF + (1|SchoolID),
  data = dt, prior_intercept = student_t(3, 470, 100),iter = iter, chains = 4,
  adapt_delta=.999,thin=10)

bsm[[3]] <- stan_lmer(
  PV1READ ~ METASUM + GFOFAIL + MASTGOAL + SWBP + WORKMAST + ADAPTIVITY + COMPETE + (1|SchoolID),
  data = dt, prior_intercept = student_t(3, 470, 100),iter = iter, chains = 4,
  adapt_delta=.999,thin=10)

bsm[[4]] <- stan_lmer(
  PV1READ ~ PERFEED + TEACHINT + BELONG + (1 + TEACHINT|SchoolID),
  data = dt, prior_intercept = student_t(3, 470, 100),iter = iter, chains = 4,
  adapt_delta=.999,thin=10)

# loo and weights
loo_bs[[1]] <- loo(log_lik(bsm[[1]]))
loo_bs[[2]] <- loo(log_lik(bsm[[2]]))
loo_bs[[3]] <- loo(log_lik(bsm[[3]]))
loo_bs[[4]] <- loo(log_lik(bsm[[4]]))

w_bs <- loo_model_weights(loo_bs, method = "stacking")
w_pbma <- loo_model_weights(loo_bs, method = "pseudobma", BB=FALSE)
w_pbmabb <- loo_model_weights(loo_bs, method = "pseudobma")


# Obtain the LPD
lpd_point <- as.matrix(cbind(loo_bs[[1]]$pointwise[, "elpd_loo"],
                             loo_bs[[2]]$pointwise[, "elpd_loo"],
                             loo_bs[[3]]$pointwise[, "elpd_loo"],
                             loo_bs[[4]]$pointwise[, "elpd_loo"]))

# klds
# bs
n_draws <- nrow(as.matrix(bsm[[1]]));print(n_draws)
ypred_bs <- matrix(NA, nrow = n_draws, ncol = nobs(bsm[[1]]))
for (d in 1:n_draws) {
  k <- sample(1:length(w_bs), size = 1, prob = w_bs)
  ypred_bs[d, ] <- posterior_predict(bsm[[k]], draws = 1)
}

y_bs <- colMeans(ypred_bs)
d1 <- density(y_bs, kernel = c("gaussian"))$y
d0 <- density(df$PV1READ, kernel = c("gaussian"))$y
kld1 <- KLD(d1, d0)$sum.KLD.py.px

# pbma
ypred_bma <- matrix(NA, nrow = n_draws, ncol = nobs(bsm[[1]]))
for (d in 1:n_draws) {
  k <- sample(1:length(w_pbma), size = 1, prob = w_pbma)
  ypred_bma[d, ] <- posterior_predict(bsm[[k]], draws = 1)
}

y_bma <- colMeans(ypred_bma)
d2 <- density(y_bma, kernel = c("gaussian"))$y
kld2 <- KLD(d2, d0)$sum.KLD.py.px

# pbmabb
ypred_bmabb <- matrix(NA, nrow = n_draws, ncol = nobs(bsm[[1]]))
for (d in 1:n_draws) {
  k <- sample(1:length(w_pbmabb), size = 1, prob = w_pbmabb)
  ypred_bmabb[d, ] <- posterior_predict(bsm[[k]], draws = 1)
}

y_bmabb <- colMeans(ypred_bmabb)
d3 <- density(y_bmabb, kernel = c("gaussian"))$y
kld3 <- KLD(d3, d0)$sum.KLD.py.px

### ::: For BHS ::: ###
d_discrete = 1
X =  dt[, c("ESCS","HOMEPOS","ICTRES",
            "JOYREAD","PISADIFF","SCREADCOMP","SCREADDIFF",
            "METASUM","GFOFAIL","MASTGOAL","SWBP","WORKMAST","ADAPTIVITY","COMPETE",
            "PERFEED","TEACHINT","BELONG")] 

stan_bhs <- list(X = X, N = nrow(X), d = ncol(X), d_discrete = d_discrete,
                 lpd_point = lpd_point, K = ncol(lpd_point), tau_mu = 1,
                 tau_sigma = 1, tau_discrete = .5, tau_con = 1)

fit_bhs<- stan("bhs_stan.stan", data = stan_bhs, chains = 4, iter = iter)

# weights
wts_bhs <- rstan::extract(fit_bhs, pars = 'w')$w
w_bhs_r <- apply(wts_bhs, c(2,3), mean)
w_bhs_m <- as.matrix(apply(wts_bhs, 3, mean))

# Obtain the KLD
ypred_bhs_r <- matrix(NA, nrow = n_draws, ncol = nobs(bsm[[1]]))
for (d in 1:n_draws) {
  k <- sample(1:4, size = 1, prob = w_bhs_m)
  ypred_bhs_r[d, ] <- posterior_predict(bsm[[k]], draws = 1)
}

y_bhs_r <- colMeans(ypred_bhs_r)

# KLD
d4 <- density(y_bhs_r, kernel = c("gaussian"))$y
kld4 <- KLD(d4, d0)$sum.KLD.py.px

# summarize the weights and lpd
wr_full <- data.frame(as.matrix(w_bs), as.matrix(w_pbma), as.matrix(w_pbmabb), w_bhs_m)
colnames(wr_full) <- c("bs","pbma", "pbmabb", "bhs")

klds_full <- rbind(kld1, kld2, kld3, kld4)

wr;wr_full

klds;klds_full

