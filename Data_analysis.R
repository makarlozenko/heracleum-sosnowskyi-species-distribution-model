output_dir <- file.path(getwd(), "plot")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

library(ggplot2)

# Run from the project folder containing data/processed/model_table.csv.
d <- read.csv(file.path("data", "processed", "model_table.csv"))
stopifnot(!anyNA(d$y), setequal(d$y, c(0, 1)))

# Climate, distances, land cover, correlations and sample sizes.
colors <- c('#6DCDF4','#78003F')
group <- factor(d$y,levels=c(0,1),labels=c('Background','Presence'))
climate <- c('bio1_temp_mean_c','bio4_temp_sd_x100','bio8_temp_wettest_quarter_c','bio12_precip_annual_mm','bio13_precip_wettest_month_mm','elevation_m')
names_climate <- c('Annual temperature (C)','Temperature SD (C)','Wettest-quarter temp. (C)','Annual rainfall (mm)','Wettest-month rain (mm)','Elevation (m)')
ds <- d
ds$bio4_temp_sd_x100 <- ds$bio4_temp_sd_x100/100
start <- function(name,height) {
  png(file.path(output_dir,paste0(name,'.png')),width=6.4,height=height,units='in',res=300,pointsize=10)
  par(family='sans',fg='#253333',col.axis='#253333',col.lab='#253333',col.main='#253333',
      oma=c(0,0,2.2,0))
}
finish <- function(title) {
  mtext(title,side=3,outer=TRUE,line=.6,font=2,cex=1.1)
  dev.off()
}
for (kind in c('climate','climate_densities')) {
  start(kind,3.0)
  par(mfrow=c(2,3),mar=c(2.8,3.1,1.8,.6),mgp=c(1.8,.5,0),tcl=-.2,cex.axis=.83,cex.lab=.83)
  for (i in seq_along(climate)) {
    x <- ds[[climate[i]]]
    if (kind=='climate') {
      boxplot(x~group,horizontal=TRUE,col=colors,outline=TRUE,pch=16,cex=.23,main=names_climate[i],cex.main=.85,yaxt='n',xlab='',ylab='',bty='n')
      axis(2,at=1:2,labels=c('BG','HS'),las=1,tick=FALSE,cex.axis=.85)
    } else {
      a <- density(x[d$y==0]); b <- density(x[d$y==1])
      plot(a,type='n',xlim=range(a$x,b$x),ylim=c(0,max(a$y,b$y)),main=names_climate[i],cex.main=.85,xlab='',ylab='Density',bty='n')
      polygon(a,col=adjustcolor(colors[1],.2),border=NA)
      polygon(b,col=adjustcolor(colors[2],.15),border=NA)
      lines(a,col=colors[1],lwd=1.4); lines(b,col=colors[2],lwd=1.4)
    }
  }
  finish(if (kind=='climate') 'Climate and elevation' else 'Climate distributions and overlap')
}
distances <- c('distance_road_m','distance_waterway_m','distance_settlement_m')
start('distances',3.0)
par(mfrow=c(3,1),mar=c(2.1,5.4,1.3,.5),mgp=c(1.4,.4,0),tcl=-.15,cex.axis=.85)
for (i in 1:3) {
  # Same pseudo-log transform as scales::pseudo_log_trans(sigma=50).
  x <- asinh(d[[distances[i]]]/100)
  boxplot(x~group,horizontal=TRUE,col=colors,outline=TRUE,pch=16,cex=.18,xaxt='n',yaxt='n',main=c('Distance to road','Distance to waterway','Distance to settlement')[i],cex.main=.9,xlab='',ylab='',bty='n')
  ticks <- c(0,50,100,250,500,1000,2500,5000,10000)
  axis(1,at=asinh(ticks/100),labels=format(ticks,big.mark=',',trim=TRUE),cex.axis=.8)
  axis(2,at=1:2,labels=c('Background','Presence'),las=1,tick=FALSE,cex.axis=.9)
}
finish('Distances to landscape features')
fractions <- c('lc_fraction_artificial','lc_fraction_agriculture','lc_fraction_forest_seminatural','lc_fraction_wetland','lc_fraction_water')
cover_names <- c('Artificial surfaces','Agriculture','Forest / semi-natural','Wetlands','Water bodies')
start('fractions',2.65)
par(mar=c(3,9,.5,1.2),mgp=c(1.9,.5,0),tcl=-.2,cex.axis=.9)
means <- sapply(fractions,function(k) tapply(100*d[[k]],group,mean))
p <- barplot(means[,5:1],beside=TRUE,horiz=TRUE,col=colors,border=NA,xlim=c(0,75),names.arg=rev(cover_names),las=1,cex.names=.9,xlab='Mean share of cell area (%)')
text(means[,5:1]+1.1,p,labels=sprintf('%.1f%%',means[,5:1]),pos=4,cex=.83)
legend('bottomright',legend=c('Background','Presence'),fill=colors,bty='n',cex=.85)
finish('Average land cover within a cell')
variables <- c(climate,distances,fractions)
short <- c('Annual temp.','Temp. SD','Wet-quarter T','Annual rain','Wet-month rain','Elevation','Road distance','Waterway dist.','Settlement dist.','Artificial','Agriculture','Forest','Wetland','Water')
rho <- cor(d[variables],method='spearman')
start('correlations',4.85)
par(mar=c(7.5,8,1,1.3),mgp=c(1.5,.4,0),tcl=0,cex.axis=.82)
plot(NA,xlim=c(.5,14.5),ylim=c(.5,14.5),xaxs='i',yaxs='i',xaxt='n',yaxt='n',xlab='',ylab='',bty='n')
palette <- colorRampPalette(c('#6DCDF4','white','#78003F'))(201)
for(i in 1:14) for(j in 1:14) {
  r <- rho[j,i]; rect(i-.5,15-j-.5,i+.5,15-j+.5,col=palette[round((r+1)*100)+1],border='white',lwd=.5)
  text(i,15-j,sprintf('%.2f',ifelse(abs(r)<.005,0,r)),cex=.68,col=ifelse(r>.65,'white','#111111'))
}
axis(2,at=14:1,labels=short,las=1,tick=FALSE,cex.axis=.83)
text(1:14,par('usr')[3]-.35,labels=short,srt=50,adj=1,xpd=NA,cex=.83)
mtext('Spearman correlation: blue = negative, white = 0, purple = positive',side=1,line=6.2,cex=.8)
finish('Correlations among main predictors')
start('counts',1.1)
par(mar=c(2.5,7,.3,1),mgp=c(1.5,.4,0),tcl=-.2)
n <- as.numeric(table(group))
p <- barplot(n,horiz=TRUE,col=colors,border=NA,names.arg=levels(group),las=1,xlim=c(0,10500),xlab='Number of cells',cex.names=.9,cex.axis=.85,cex.lab=.9)
text(n+150,p,labels=paste0(format(n,big.mark=',',trim=TRUE),' (',round(100*n/sum(n)),'%)'),pos=4,cex=.9)
finish('Cells in the analysis')

# Standardised mean differences.
v <- c('lc_fraction_artificial','bio4_temp_sd_x100','elevation_m','bio8_temp_wettest_quarter_c','lc_fraction_water','distance_waterway_m','lc_fraction_agriculture','lc_fraction_wetland','lc_fraction_forest_seminatural','distance_settlement_m','bio1_temp_mean_c','bio12_precip_annual_mm','bio13_precip_wettest_month_mm','distance_road_m')
labels <- c('Artificial surfaces','Temperature seasonality','Elevation','Wettest-quarter temperature','Water bodies','Distance to waterway','Agriculture','Wetlands','Forest / semi-natural','Distance to settlement','Annual mean temperature','Annual precipitation','Wettest-month precipitation','Distance to road')
smd <- sapply(v,function(k) {a <- d[d$y==1,k]; b <- d[d$y==0,k]; (mean(a)-mean(b))/sqrt(((length(a)-1)*var(a)+(length(b)-1)*var(b))/(length(a)+length(b)-2))})
png(file.path(output_dir,'differences.png'),width=6.4,height=3.25,units='in',res=300,pointsize=9)
par(mar=c(3.2,10,0.5,2),mgp=c(2,0.6,0),tcl=-.2,family='sans',las=1,
    oma=c(0,0,2.2,0))
y <- 14:1
plot(smd,y,type='n',xlim=c(-.45,.6),ylim=c(.5,14.5),yaxt='n',xlab='Standardised mean difference (pooled SD)',ylab='',bty='n',cex.axis=.9,cex.lab=.95)
abline(v=seq(-.4,.6,.2),col='#ECECEC',lwd=.6)
abline(v=0,col='#667777',lty=2)
segments(0,y,smd,y,col='#B7BDBD',lwd=1.2)
points(smd,y,pch=19,col='#78003F',cex=.85)
axis(2,at=y,labels=labels,tick=FALSE,cex.axis=.85)
text(smd,y,labels=sprintf('%+.2f',smd),pos=ifelse(smd<0,2,4),offset=.55,cex=.75,col='#333333')
finish('Standardised mean differences')

# Monthly climate differences (the original Overleaf heatmap).
monthly <- grep("^(tavg|tmin|tmax|prec)_[0-9]{2}$", names(d), value = TRUE)
effect_table <- do.call(rbind, lapply(monthly, function(variable) {
  x0 <- d[d$y == 0, variable]
  x1 <- d[d$y == 1, variable]
  x0 <- x0[is.finite(x0)]
  x1 <- x1[is.finite(x1)]
  pooled_sd <- sqrt(((length(x0) - 1) * var(x0) + (length(x1) - 1) * var(x1)) /
                      (length(x0) + length(x1) - 2))
  data.frame(variable = variable, difference = (mean(x1) - mean(x0)) / pooled_sd)
}))
theme_set(theme_minimal(base_size = 13) +
            theme(legend.position = "bottom", legend.title = element_blank(),
                  panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
                  panel.spacing = grid::unit(1.4, "lines"),
                  strip.text = element_text(face = "bold", size = 13),
                  plot.title = element_text(face = "bold", size = 19, hjust = .5),
                  plot.title.position = "plot",
                  plot.subtitle = element_text(size = 12, hjust = .5, margin = margin(b = 14)),
                  plot.margin = margin(15, 20, 15, 20)))

monthly_effects <- effect_table[effect_table$variable %in% monthly, ]
monthly_effects$month <- as.integer(sub(".*_", "", monthly_effects$variable))
monthly_effects$type <- factor(sub("_.*", "", monthly_effects$variable),
                              levels = c("prec", "tmax", "tmin", "tavg"),
                              labels = c("Precipitation", "Maximum temperature", "Minimum temperature", "Mean temperature"))
effect_limit <- max(abs(monthly_effects$difference))
monthly_effects$label <- sprintf("%+.2f", ifelse(abs(monthly_effects$difference) < .005, 0, monthly_effects$difference))
monthly_plot <- ggplot(monthly_effects, aes(month, type, fill = difference)) +
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

ggsave(file.path(output_dir, "monthly_differences.png"), monthly_plot,
       device = grDevices::png, width = 15, height = 6, units = "in",
       dpi = 300, bg = "white")
message("Saved 8 final PNG figures to: ", output_dir)
