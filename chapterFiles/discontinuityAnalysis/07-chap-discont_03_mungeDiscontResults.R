# Setup -------------------------------------------------------------------
## Clear mem
rm(list = ls())

## Load pkgs
library(cowplot)
library(tidyverse)

# 1. Load BBS data into mem -------------------------------------------------
### THIS SECTION NEEDS TO BE SOURCED BEFORE ANY OTHER DATA OR FUNCTIONS ARE ADDED TO MEMORY!
## Source the script that returns the obkect `feathers.subset`, which si the BBS data + sampling gridded subsetted data
source(
  here::here(
    "/chapterFiles/discontinuityAnalysis/07-chap-discont_01_getBBSdata.R"
  )
)
# takes about thirty to sixty seconds......

## This will return a few objects:
### 1. bbsData - containes the subsetted data and munged species/aou and body masses. This df also includes presence absence data for 3-year aggregates
### 2. grassSpecies - some grassland obligate spp of interest
### 3. routes_gridList - the grid design assosciation with rowID and colID on the bbsData


# 2. Source helper functions -------------------------------------------------
(to.source <-
   list.files(
     here::here("/chapterFiles/discontinuityAnalysis/"),
     pattern = "helper",
     full.names = TRUE
   ))
for (i in 1:length(to.source))
  source(to.source[i])

## Source helper funs for plotting spatial data located in another chapter!
source(
  here::here(
    "/chapterFiles/fisherSpatial/04-chap-fisherSpatial_helperFunctions.R"
  )
)


# 3. Define, create directories -------------------------------------
## discontinuity results location
resultsDir <-
  here::here("/chapterFiles/discontinuityAnalysis/results/")

## figures
figDirTemp <-
  here::here("/chapterFiles/discontinuityAnalysis/tempFigs/")
figDir <-
  here::here("/chapterFiles/discontinuityAnalysis/figsCalledInDiss/")
tabDir <-
  here::here("/chapterFiles/discontinuityAnalysis/tabsCalledInDiss/")
suppressWarnings(dir.create(figDir))
suppressWarnings(dir.create(figDirTemp))
suppressWarnings(dir.create(tabDir))

# 4. Merge discontinuity results and bbs dat -----------------------------------------------------------
# Import the discontinuity analysis results
gaps <-
  loadResultsDiscont(resultsDir = resultsDir, myPattern = "discont") %>%
  mutate(loc = as.factor(paste(countrynum, statenum, route, sep = "_")))

# Join the results with the locations of the BBS routes
gaps <-
  left_join(gaps, bbsData)


## Load the GRI 'constant power table'
pwr <-
  read_csv(here::here(
    "chapterFiles/discontinuityAnalysis/griConstantPowerTable.csv"
  ))

## Use linear apprxoimation to get richness for every integer between 20 and 300
pwr.approx <-
  approx(
    x = pwr$richness,
    y = pwr$threshold,
    xout = seq(from = 20, to = 300)
  ) %>%
  as_tibble() %>%
  rename(richness = x, powerConstant = y)

## Append species richenss to gap data
gaps.bbs <- gaps %>%
  group_by(countrynum, statenum, route, year) %>%
  mutate(richness = n_distinct(species)) %>% ungroup() %>%
  left_join(pwr.approx) %>%
  ungroup() %>%
  ## Add new column for GRI constant pwoer threshold level%>%
  mutate(isGap.powerConstant = ifelse(gap.percentile >= powerConstant, "yes", "no")) %>%
  mutate(isGap.percentile = ifelse(gap.percentile >= 0.90, "yes", "no"))

# rm(gaps)

# 5. Identify things associated with Roberts et al.spatial regimes -------------------------------
## year and location of their proposed regime shifts
rs.loc <- data.frame(year = c(1970, 1985, 2000, 2015),
                     lat = c(39, 39.5, 40, 40.5))

# Identify which routes to highlight
rtesOfInterest <-
  paste0("840_38_", c(25, 28, 29, 31)) ## these are the routes nearest teh reigm eshift locations


# 6. Munge results -----------------------------------------------------------
gaps.bbs <-
  gaps.bbs %>%
  group_by(year, countrynum, statenum, route) %>%
  arrange(year, countrynum, statenum, route, log10.mass) %>%
  mutate(
    rank = 1:n(),
    edgeSpp  = ifelse(
      lag(isGap.percentile) == "yes" |
        isGap.percentile == "yes" ,
      "yes",
      "no"
    ),
    edgeSpp  = ifelse(
      log10.mass == min(log10.mass) |
        log10.mass == max(log10.mass),
      "yes" ,
      edgeSpp
    )
  ) %>%
  ungroup() %>%
  mutate(
    rs.1970 = ifelse(lat < rs.loc$lat[1], "below", "above"),
    rs.1985 = ifelse(lat < rs.loc$lat[2], "below", "above"),
    rs.2000 = ifelse(lat < rs.loc$lat[3], "below", "above"),
    rs.2015 = ifelse(lat < rs.loc$lat[4], "below", "above"),
    rs.all = ifelse((rs.1970 == rs.1985) &
                      (rs.2000 == rs.1985) & (rs.2000 == rs.2015),
                    rs.1970,
                    "different"
    )
  )

### Append a number for each aggregation and create a new df called 'results'
loc.ind <- unique(gaps.bbs$loc)
for (i in seq_along(loc.ind)) {
  if (i == 1)
    results <- NULL
  ## go along each country/state/route location
  temp1 <- gaps.bbs %>%
    filter(loc == loc.ind[i])
  
  year.ind <- unique(temp1$year)
  
  df.out <- NULL
  for (h in seq_along(year.ind)) {
    temp <-  temp1 %>%
      filter(year == year.ind[h])
    
    # setup for j loop
    x = temp$edgeSpp
    agg.vec  = rep(1, length.out = length(x))
    counter <- 1
    
    ## Create a vector of aggregation numbers for all rows in temp
    for (j in 2:length(x)) {
      # browser()
      agg.vec[j] <- counter
      
      if (j != length(x) &
          x[j] == "yes" &  x[j + 1] == "yes")
        counter <- counter + 1
      
      if (j == length(x))
        agg.vec[j] = counter  # ensure the last one takes on current counter...
    } # end j loop
    
    temp$aggNumber = agg.vec
    df.out <- bind_rows(temp, df.out)
  } # end h loop
  
  results <- bind_rows(results, df.out)
  
} # end i-loop
if (nrow(gaps.bbs) != nrow(results))stop("results arent same size as selectgapsbbs")


# MUNGE RESULTS SOME MORE!
results <- results %>%
  group_by(year, loc, aggNumber) %>%
  mutate(
    distEdge.left = abs(log10.mass - min(log10.mass)),
    distEdge.right = abs(log10.mass - max(log10.mass))
  ) %>%
  ungroup() %>%
  mutate(distEdge = ifelse(distEdge.left < distEdge.right, distEdge.left, distEdge.right)) %>%
  group_by(year, countrynum, statenum, route) %>%
  mutate(nAggs = n_distinct(aggNumber),
         nSpp  = n_distinct(scientificName)) %>%
  ungroup() %>%
  mutate(
    is.declining = ifelse(aou %in% decliningSpecies$aou, "yes", "no"),
    is.grassland = ifelse(aou %in% grassSpecies$aou, "yes", "no"),
    is.grassDeclining = ifelse((aou %in% decliningSpecies$aou &
                                  aou %in% grassSpecies$aou),
                               "yes",
                               "no"
    )
  ) %>%
  ## scale distanace to edge within each route-year
  group_by(year, loc) %>%
  mutate(distEdge.scaled = scale(distEdge, center = TRUE)) %>%
  ungroup() %>%
  mutate(regime = "WRONGWRONGWRONG") %>% 
  mutate(year = as.numeric(year))


## Add N/S regime -- I tried tidying but it wasn't working properly so eh
### during and before year 1 
results[results$year < rs.loc$year[1] & results$lat <= rs.loc$lat[1], ]$regime="South"
results[results$year < rs.loc$year[1] & results$lat > rs.loc$lat[1], ]$regime="North"
### For during  year 1 and  before 2
results[results$year >= rs.loc$year[1] & results$year < rs.loc$year[2] & results$lat <= rs.loc$lat[2], ]$regime="South"
results[results$year >= rs.loc$year[1] & results$year < rs.loc$year[2] & results$lat >  rs.loc$lat[2], ]$regime="North"
### For during  year 2 and  before 3
results[results$year >= rs.loc$year[2] & results$year < rs.loc$year[3] & results$lat <= rs.loc$lat[3], ]$regime="South"
results[results$year >= rs.loc$year[2] & results$year < rs.loc$year[3] & results$lat >  rs.loc$lat[3],  ]$regime="North"
### For during  year 3 and  before 4
results[results$year >= rs.loc$year[3] & results$year < rs.loc$year[4] & results$lat <= rs.loc$lat[4], ]$regime="South"
results[results$year >= rs.loc$year[3] & results$year < rs.loc$year[4] & results$lat >  rs.loc$lat[4],  ]$regime="North"
### For after year 4
### For dring and after eyar 4
results[results$year >= rs.loc$year[4] & results$lat <= rs.loc$lat[4], ]$regime="South"
results[results$year >= rs.loc$year[4] & results$lat > rs.loc$lat[4], ]$regime="North"


## ENSURE THE N-S split occurs at correct latitude/year
# View(results %>% distinct(year, loc, regime, lat, long) %>% arrange(year, lat))
ggplot(
  results %>% group_by(year, regime) %>% summarise(y = n_distinct(loc)) %>% ungroup(),
  aes(year, y)
) + geom_boxplot() + facet_wrap( ~ regime)

## Munge some more...
results <-    
  results %>%
  group_by(loc) %>%
  mutate(regimeShift = ifelse(n_distinct(regime) == 1, "no", "yes")) %>%
  ungroup() %>%
  mutate(
    is.declining = ifelse(aou %in% decliningSpecies$aou, "yes", "no"),
    is.grassland = ifelse(aou %in% grassSpecies$aou, "yes", "no"),
    is.grassDeclining = ifelse((aou %in% decliningSpecies$aou &
                                  aou %in% grassSpecies$aou),
                               "yes",
                               "no"
    )
  )

## ensure df has factors
vars <-
  c("regime",
    "is.declining",
    "is.grassland",
    "is.grassDeclining",
    "loc",
    "commonName")
results[vars] <- lapply(results[vars], factor)

# 7. Save tables to file for diss --------------------------------------------
## summary table to file for n routes per regime per year
saveTab(
  tab = results %>%  distinct(year, regime, loc) %>%
    group_by(year, regime) %>%
    summarise(nLoc = n()),
  fn = "nRtesPerRegimePerYear",
  dir = tabDir
)

## summary of grassland and declinilng species in a table
saveTab(
  tab = full_join(
    grassSpecies %>% mutate(id = "grass"),
    decliningSpecies %>% mutate(id = "declining")
  ),
  fn = "grassDeclSppList"
)



# 8. Species turnover within locations  ----------------------------------------------------------------------
## Define some years for simplifying plots
year.ind <-c(rs.loc$year + 5, rs.loc$year, rs.loc$year + 10) 

# Get lag-1 year turnover
turnover <- bbsData %>%
  mutate(loc = as.factor(paste(countrynum, statenum, route, sep = "_"))) %>%
  dplyr::select(year, loc,  aou) %>%
  group_by(loc, year) %>%
  summarise(nSpp = n_distinct(aou)) %>%
  ungroup() %>%
  spread(key = "year", value = "nSpp") %>%
  gather(key = "year", value = "nSpp",-loc) %>%
  # group_by(countrynum, statenum, route, year) %>%
  mutate(nSppDiff = nSpp - lag(nSpp),
         year = as.integer(year))


# Base histogram  - distribution of turnover ranges
par(mfrow = c(1, 2))
hist(turnover$nSpp, xlab = "species richness", main = "")
hist(turnover$nSppDiff, xlab = "turnover", main = "")
par(mfrow = c(1, 1))

require(ggridges)
# fancier historgrams
(
  p = ggplot(
    turnover %>%  filter(year %in% year.ind),
    aes(x = nSpp, y = year,
        fill = as.factor(year))
  ) +
    geom_density_ridges(
      show.legend = F,
      stat = "binline",
      draw_baseline = F,
      scale = 2, alpha=0.4
    ) +
    theme_ridges() +
    xlab("route-level annual species richness")+
    scale_fill_colorblind()
)
saveFig(p = p, dir = figDir, fn = "richnessByYear")


(p <- ggplot(turnover %>%  filter(
  !is.na(nSppDiff),
  year %in% year.ind
),
aes(x = nSppDiff, y = year, fill = as.factor(year))) +
    geom_density_ridges(show.legend = F, scale = 4, alpha=0.6) +
    theme_ridges() +
    xlab("route-level annual species turnover")+
    theme_ridges()+
    scale_fill_colorblind()
  
)
saveFig(p = p, dir = figDir, fn = "turnoverByYear")

# Lineplot of mean turnover and lag-1 turnover across routes
temp <- turnover %>%
  group_by(year) %>%
  summarise(mean = mean(nSppDiff, na.rm = TRUE),
            sd = sd(nSppDiff, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(upper    = 1.96 * sd + mean,
         lower    = mean - 1.96 * sd)


(
  p.turn <- ggplot(data = temp) +
    geom_line(aes(x = year, y = mean), size=1) +
    ylab(expression("mean annual \n turnover (\u00B1 95 %CI)")) +
    # ylab(expression(mu*" annual species turnover (?95% CI)"))+
    geom_ribbon(aes(
      x = year, ymax = lower, ymin = upper
    ), alpha = 0.20) +
    theme_Publication()
)

saveFig(p = p.turn, fn = "meanAnnualTurnover")

## Table of richness stats
tab1 <-
  turnover %>% 
  ## summary stats for richness
  group_by(year) %>% 
  na.omit(nSpp) %>% 
  summarise(meanRich = mean(nSpp, na.rm =T), 
            sdRich = sd(nSpp, na.rm =T), 
            sampSizeRich = n_distinct(loc)) 
## Table of turnover stats
tab2 <- turnover %>% 
  ## summary stats for annual turnover
  group_by(year) %>% 
  na.omit(nSppDiff) %>% 
  summarise(meanTurn = mean(nSppDiff, na.rm =T), 
            sdTurn = sd(nSppDiff, na.rm =T), 
            sampSizeTurn = n_distinct(loc))

tab3 <- full_join(tab1, tab2); rm(tab2, tab1)
saveTab(tab = tab3, dir = tabDir, fn="richTurnStatsTab")

# # 9. Plot the discontinuity results ------------------------------------------
thresh = 0.90 # define threshold
# year.ind <- unique(gaps.bbs$year)
year.ind <- c(1970,1985,  2000, 2015)

# gap.stat <- "isGap.powerConstant" ## whihc gap stat to plot
gap.stat <- "isGap.percentile" ## whihc gap stat to plot

for (j in seq_along(unique(gaps.bbs$statenum))) {
  state.ind = unique(gaps.bbs$statenum)[j]
  temp1 <- gaps.bbs %>%
    filter(year %in% year.ind,
           statenum == state.ind)
  
  for (i in seq_along(unique(temp1$route))) {
    route.ind <- unique(temp1$route)[i]
    temp <- temp1 %>%
      filter(countrynum == 840,
             route == route.ind) %>%
      group_by(year, countrynum, statenum, route) %>%
      arrange(year, loc, log10.mass) %>%
      mutate(
        rank = 1:n(),
        edgeSpp  = ifelse(lag(!!sym(gap.stat)) == "yes" |
                            !!sym(gap.stat) == "yes" , "yes", "no"),
        edgeSpp  = ifelse(
          log10.mass == min(log10.mass) |
            log10.mass == max(log10.mass),
          "yes" ,
          edgeSpp
        )
      ) %>%
      ungroup()
    # View(temp)
    ## Define xlim for aligning the plot_grid plots
    ylims <- c(min(temp$log10.mass), max(temp$log10.mass))
    
    p1 <-
      ggplot(data = temp %>% filter(year == year.ind[1]),
             aes(x = rank, y = log10.mass)) +
      geom_point(aes(color = edgeSpp, shape = edgeSpp)) +
      scale_color_manual(values = c("yes" = "red", "no" = "black")) +
      scale_shape_manual(values = c("yes" = 17, "no" = 16)) +
      theme_bw() +
      ylab("") +
      xlab("") +
      ylim(c(ylims)) +
      labs(caption = "")
    # p1
    p2 <-
      ggplot(data = temp %>% filter(year == year.ind[2]),
             aes(x = rank, y = log10.mass)) +
      geom_point(aes(color = edgeSpp, shape = edgeSpp)) +
      scale_color_manual(values = c("yes" = "red", "no" = "black")) +
      scale_shape_manual(values = c("yes" = 17, "no" = 16)) +
      theme_bw() +
      ylab("") +
      xlab("") +
      ylim(c(ylims)) +
      labs(caption = "")
    # p2
    
    p3 <-
      ggplot(data = temp %>% filter(year == year.ind[3]),
             aes(x = rank, y = log10.mass)) +
      geom_point(aes(color = edgeSpp, shape = edgeSpp)) +
      scale_color_manual(values = c("yes" = "red", "no" = "black")) +
      scale_shape_manual(values = c("yes" = 17, "no" = 16)) +
      theme_bw() +
      ylim(c(ylims)) +
      ylab("") +
      xlab("") +
      labs(caption = "")
    
    p4 <-
      ggplot(data = temp %>% filter(year == year.ind[3]),
             aes(x = rank, y = log10.mass)) +
      geom_point(aes(color = edgeSpp, shape = edgeSpp)) +
      scale_color_manual(values = c("yes" = "red", "no" = "black")) +
      scale_shape_manual(values = c("yes" = 17, "no" = 16)) +
      theme_bw() +
      ylim(c(ylims)) +
      ylab("") +
      xlab("") +
      labs(caption = "")
    
    
    require(grid)
    require(gridExtra)
    prow <-
      cowplot::plot_grid(
        p1 + theme(legend.position = "none"),
        p2 + theme(legend.position = "none"),
        p3 + theme(legend.position = "none"),
        p4 + theme(legend.position = "none"),
        ncol = 2,
        labels = c(year.ind),
        hjust = -1.3,
        vjust = 1.8,
        align = "v"
      )
    
    
    y.grob <- textGrob(
      "log mass",
      gp = gpar(
        fontface = "bold",
        col = "blue",
        fontsize = 12
      ),
      rot = 90
    )
    
    x.grob <- textGrob("rank",
                       gp = gpar(
                         fontface = "bold",
                         col = "blue",
                         fontsize = 12
                       ))
    
    p <- plot_grid(prow,
                   # legend_b,
                   ncol = 1, rel_heights = c(1, .4))
    
    #add to plot
    p <-
      grid.arrange(arrangeGrob(p, left = y.grob, bottom = x.grob))
    
    
    fn <- paste0(gap.stat, "_state", state.ind, "_rte", route.ind)
    # saveFig(p = p, fn=fn, dir=figDirTemp)
    
    ## Add grassland obligate species symbols to the plots
    test <- temp %>% filter(aou %in% grassSpecies$aou) %>%
      dplyr::select(year, commonName, aou, log10.mass, rank)
    
    prow <-
      cowplot::plot_grid(
        addGrassSppLabels(p1) + theme(legend.position = "none"),
        addGrassSppLabels(p2) + theme(legend.position =
                                        "none"),
        addGrassSppLabels(p3)  + theme(legend.position =
                                         "none"),
        addGrassSppLabels(p4)  + theme(legend.position =
                                         "none"),
        ncol = 2,
        labels = c(year.ind),
        hjust = -1.3,
        vjust = 1.8,
        align = "v"
      )
    
    
    y.grob <- textGrob(
      "log mass",
      gp = gpar(
        fontface = "bold",
        col = "blue",
        fontsize = 12
      ),
      rot = 90
    )
    
    x.grob <- textGrob("rank",
                       gp = gpar(
                         fontface = "bold",
                         col = "blue",
                         fontsize = 12
                       ))
    
    p <- plot_grid(prow,
                   # legend_b,
                   ncol = 1, rel_heights = c(1, .4))
    
    #add to plot
    p <-
      grid.arrange(arrangeGrob(p, left = y.grob, bottom = x.grob))
    
    
    fn <-
      paste0(gap.stat,
             "_withGrassObligates_state",
             state.ind,
             "_rte",
             route.ind)
    saveFig(p = p, fn = fn, dir = figDirTemp)
    rm(p, p1, p2, p3, p4, prow)
    
    
  }
}


# 10. Create and plot grassland, declining species results --------------------
declining.results <- results %>%
  filter(commonName %in% decliningSpecies$commonName)

grass.results <- results %>%
  filter(commonName %in% grassSpecies$commonName)

grassDeclining.results <- results %>%
  filter(
    commonName %in% grassSpecies$commonName,
    commonName %in% decliningSpecies$commonName
  )



(
  p1 <- ggplot(declining.results , aes(x = factor(year),
                                       y = distEdge)) +
    geom_boxplot(outlier.shape = 1, show.legend = FALSE) +
    # geom_jitter(width = 0.2, show.legend = FALSE)+
    ggtitle("Declining species in all routes")+
    ylab("distance to edge") + xlab("year") +
    theme(axis.text.x = element_text(angle = 90))
)
saveFig(p = p1, fn = "distEdge_decliningSpp_allRoutes", dir = figDirTemp)

(
  p2 <- ggplot(
    declining.results %>%
      filter(loc %in% rtesOfInterest),
    aes(x = factor(year), y = distEdge)
  ) + #, color=log10.mass))+
    geom_boxplot(outlier.shape = 1, show.legend = FALSE) +
    # geom_jitter(width = 0.2, show.legend = FALSE)+
    ylab("distance to edge") + xlab("year") +
    ggtitle("Declining species in select routes")+
    theme(axis.text.x = element_text(angle = 45,vjust = .5))
)
saveFig(p = p2, fn = "distEdge_decliningSpp_selectRoutes", dir = figDirTemp)

(
  p11 <- ggplot(grass.results, aes(x = factor(year), y = distEdge)) +
    geom_boxplot(outlier.shape = 1) +
    # geom_jitter(width = 0.2)+
    ylab("distance to edge") + xlab("year") + ggtitle("Grassland obligates in all routes")+
    theme(axis.text.x = element_text(angle = 90))
)
saveFig(p = p11, fn = "distEdge_grassSpp_allRoutes", dir = figDirTemp)

(
  p22 <-
    ggplot(
      grass.results %>% filter(loc %in% rtesOfInterest),
      aes(
        y = factor(commonName),
        x = distEdge,
        color = factor(regime)
      )
    ) +
    geom_point(show.legend = FALSE) +
    geom_jitter(width = 0.2, show.legend = FALSE) +
    ylab("") + xlab("distance to edge") + ggtitle("Declining grassland obligates in select routes")
  
)
saveFig(p = p22, fn = "distEdge_grassSpp_selectRoutes", dir = figDirTemp)

(
  p111 <-
    ggplot(
      grassDeclining.results,
      aes(
        y = factor(commonName),
        x = distEdge,
        color = factor(regime)
      )
    ) +
    geom_point(show.legend = FALSE) +
    geom_jitter(width = 0.2, show.legend = FALSE) +
    ylab("") + xlab("distance to edge") + ggtitle("Declining grassland obligates in all routes")
  # +
  #   theme(axis.text.x = element_text(angle = -45, vjust=.4, hjust=.1))
)
saveFig(p = p111, fn = "distEdge_grassDeclinSpp_allRoutes", dir = figDirTemp)

(
  p222 <-
    ggplot(
      grassDeclining.results %>% filter(loc %in% rtesOfInterest),
      aes(
        x = factor(commonName),
        y = distEdge,
        color = factor(year)
      )
    ) + #, color=log10.mass))+
    geom_boxplot(show.legend = FALSE, outlier.shape = 2) +
    # geom_jitter(width = 0.2)+
    ylab("distance to edge") + xlab("year") + ggtitle("Declining grassland obligates in select routes")
)
saveFig(p = p222, fn = "distEdge_grassDeclinSpp_selectRoutes", dir = figDirTemp)

(
  p3 <-
    ggplot(
      results %>% filter(loc %in% rtesOfInterest),
      aes(x = factor(year), y = distEdge)
    ) + #, color=log10.mass))+
    geom_boxplot(outlier.shape = 1, show.legend = FALSE) +
    theme(axis.text.x = element_text(angle = 90))+
    # geom_jitter(width = 0.2)+
    ylab("distance to edge") + xlab("year") + ggtitle("All species in routes \nnear regime shift")
)
saveFig(p = p3, fn = "distEdge_allSpp_selectRoutes", dir = figDirTemp)

(
  p33 <- ggplot(
    results %>%
      filter(loc %in% rtesOfInterest) %>%
      mutate(
        is.grass = ifelse(commonName %in% grassSpecies$commonName, "yes", "no")
      ),
    aes(x = factor(year), y = distEdge, color = is.grass)
  ) +
    geom_boxplot(outlier.shape = 1) + #geom_jitter(width = 0.2)+
    theme(axis.text.x = element_text(angle = 90))+
    labs(color="Grassland\nobligate")+
    scale_color_colorblind()+
    ylab("distance to edge") + xlab("year") + ggtitle("All species in select routes")
)
saveFig(p = p33, fn = "distEdge_allSpp_selectRoutes_grassYN", dir = figDirTemp)

(
  p3333 <-
    ggplot(
      results %>% filter(loc %in% rtesOfInterest) %>% mutate(
        is.declining = ifelse(commonName %in% decliningSpecies$commonName, "yes", "no")
      ),
      aes(x = factor(year), y = distEdge, color = is.declining)
    ) +
    geom_boxplot(outlier.shape = NA) + #geom_jitter(width = 0.2)+
    labs(color="Declining\nspecies")+
    scale_color_colorblind()+
    ylab("distance to edge") + xlab("year") + ggtitle("All species in select routes")
)
saveFig(p = p3333, fn = "distEdge_allSpp_selectRoutes_decliningYN", dir = figDirTemp)


(
  p4 <- ggplot(results, aes(x = factor(year), y = distEdge,color=regime)) +
    geom_boxplot(outlier.shape = 1) +
    labs(color="Regime")+
    scale_color_colorblind()+
    theme(axis.text.x = element_text(angle = 90))+
    # geom_jitter(width = 0.2) +
    ylab("distance to edge") + xlab("year") + ggtitle("All species in all routes")
)
saveFig(p = p4, fn = "distEdge_allSpp_allRoutes", dir = figDirTemp)


# 11. Correlation of distance to edge with body mass --------------------------
cor.tab <-function(x, y, x.lab, y.lab, method="pearson"){
  
  t <- cor.test(x, y)
  
  
  cor.tab <- tibble(
    x = x.lab, 
    y = y.lab, 
    cor =  t$estimate,
    p = t$p.value,
    # cor.stat = t$s,tistic
    df = t$parameter,
    nullH = t$null.value,
    altH  = t$alternative,
    method = t$method,
    lwr = t$conf.int[1],
    upper= t$conf.int[2]
  )
  
  return(cor.tab)
  
}

cor.table <- bind_rows(cor.tab(results$distEdge,results$log10.mass, x.lab="distEdge", y.lab="log10.mass"),
                       cor.tab(grass.results$distEdge,grass.results$log10.mass, x.lab="distEdge", y.lab="log10.mass"),
                       cor.tab(grassDeclining.results$distEdge,grassDeclining.results$log10.mass, x.lab="distEdge", y.lab="log10.mass"),
                       cor.tab(declining.results$distEdge,declining.results$log10.mass, x.lab="distEdge", y.lab="log10.mass")) %>% 
  mutate(name = c(
    "all","grass", "grassDeclin","declining"))
saveTab(tab = cor.table, fn = "corTabBySppGroup", dir = tabDir)



# 12. SAVE RESULTS TO FILE FOR QUICK LOADING --------------------------------
saveRDS(
  results,paste0(resultsDir, "/datForAnova.RDS")
  )
# END RUN -----------------------------------------------------------------
