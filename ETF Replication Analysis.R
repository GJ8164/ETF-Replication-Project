############################################################
# ETF Replication & Analysis: iShares DAX UCITS ETF (EXS1.DE)
# Date: 22.09.2025
#
# Objective:
#   - Replicate the iShares DAX UCITS ETF (EXS1.DE) 
#     using its top 10 holdings.
#   - Compare replicated ETF performance vs real ETF.
#   - Evaluate tracking error, correlation, CAPM Beta.
#   - Perform event-window analysis on selected dates.
#   - Visualize cumulative returns and event effects.
############################################################

############# Install & Load Required Libraries ############

install.packages("rvest")
install.packages("quantmod")
install.packages("PerformanceAnalytics")
install.packages("timetk")
library(timetk)
library(tidyverse)
library(rvest)
library(quantmod)
library(PerformanceAnalytics)
library(zoo)

############# Step 1. Scrape ETF Top 10 Holdings ############

page <- read_html("https://www.justetf.com/en/etf-profile.html?isin=DE0005933931#overview")

top10_holdings <-page %>% 
  html_element(xpath ='//*[@id="etf-profile-body"]/div[14]/div[4]/div[1]/table') %>% 
  html_table()

colnames(top10_holdings)[1] <- "top10_holdings"
colnames(top10_holdings)[2]<- "weightage"

tickers <- c("SAP.DE","SIE.DE","ALV.DE","DTE.DE","AIR.DE","RHM.DE","MUV2.DE","ENR.DE","DBK.DE","DB1.DE")
top10_holdings$ticker <-tickers
top10_holdings <- top10_holdings[, c("top10_holdings","ticker","weightage")]

top10_holdings$weightage <- as.numeric(
  sub("%", "", top10_holdings$weightage)
  )/100

########## Step 2. Get Historical Prices of Top 10 ##########

start_date <- "2023-01-01"
end_date <- "2025-08-31"       
getSymbols(tickers,sec = 'yahoo',from = start_date, to = end_date, auto.assign = TRUE)

prices <- do.call(merge, lapply(tickers, function(t) Ad(get(t))))
colnames(prices) <- tickers
prices <- data.frame(date =index(prices), coredata(prices))

###################### Get ETF Price ########################

etf <- "EXS1.DE"
start_date <- "2023-01-01"
end_date <- "2025-08-31"

getSymbols(etf,sec = "yahoo", from = start_date, to = end_date,auto.assign = TRUE)

etf_price = get(etf)
etf_price <- data.frame(date = index(etf_price),coredata(etf_price))

etf_clean<- etf_price %>% 
  select(date, etf = EXS1.DE.Adjusted)

################# Get Benchmark (DAX Index) #################

benchmark <- "^GDAXI"
start_date <- "2023-01-01"
end_date <- "2025-08-31"

benchmark_index <- getSymbols(benchmark, sec = "yahoo",from = start_date, to = end_date, auto.assign = FALSE)

benchmark_clean <- data.frame(date = index(benchmark_index),
                           coredata(benchmark_index)) %>%
  select(date, benchmark = GDAXI.Adjusted)

####################### Merge All Data ######################

combined_df <- merge(prices,etf_clean, by = 'date', all = FALSE)
combined_df <- merge(combined_df,benchmark_clean, by = 'date', all = FALSE)
view(combined_df)

combined_df<- combined_df %>% 
  rename( EXS1.DE = etf,
         GDAXI = benchmark)

combined_df<- combined_df %>% 
  tk_xts(date_var = date)

################### Step 3. Calculate Returns ################

returns <- Return.calculate(combined_df, method = "discrete") %>% 
 na.omit()

holding_returns <- returns[, top10_holdings$ticker]

################ Step 4. Replication & Metrics ###############


replicated_etf_returns <- as.xts(
  as.matrix(holding_returns) %*% top10_holdings$weightage,
  order.by = index(holding_returns)
)
colnames(replicated_etf_returns) <- "replicated_etf"

etf_returns <- returns$EXS1.DE

cor(replicated_etf_returns, etf_returns)
tracking_error <- sd(replicated_etf_returns-etf_returns)
tracking_error
excess_return <- replicated_etf_returns - returns$GDAXI
mean(excess_return)
CAPM.beta(Ra = replicated_etf_returns, Rb = returns$GDAXI)

################## Step 5. Event Analysis ####################

event1_date <- as.Date("2025/03/31")
event2_date <- as.Date("2025/03/18")

get_event_date <- function(event_date, data_xts, window = 4 ){
  start_date <- event_date - window
    end_date <- event_date + window
    return(window_data <- data_xts[paste0(start_date, "/", end_date)])
}

event1_etf <- get_event_date(event1_date, etf_returns, window = 4)
event1_rpl_etf<- get_event_date(event1_date, replicated_etf_returns, window = 4)

event2_etf <- get_event_date(event2_date, etf_returns, window = 4)
event2_rpl_etf<- get_event_date(event2_date, replicated_etf_returns, window = 4)

# Event 1 Plot

plot_event1<- plot.zoo(cbind(event1_etf, event1_rpl_etf), plot.type = "single",
         col = c("blue", "red"), lty = 1:2,
         main = "Event 1: ETF vs Replicated ETF Returns",
         ylab = "Daily Return",
         xlab = "Timeline(2025)")
legend("topleft", legend = c("ETF", "Replicated ETF"), 
       col = c("blue", "red"),
       cex = 0.8,lty = 1:2)

# Event 2 Plot

plot_event2<-plot.zoo(cbind(event2_etf, event2_rpl_etf),plot.type = "single",
         col = c("blue", "red"), lty = 1:2,
         main = "Event 2: ETF vs Replicated ETF Returns",
         ylab = "Daily return",
         xlab = "Timeline(2025)")
legend("topright", legend = c("ETF", "ReplicatedETF Returns"),
       col = c("blue", "red"),
       cex = 0.8, lty = 1:2)

# Event differences

event1_diff <- event1_etf - event1_rpl_etf
mean(event1_diff)
sd(event1_diff)
event2_diff <- event2_etf - event2_rpl_etf
mean(event2_diff)
sd(event2_diff)

################## Step 6. Cumulative Returns ################

cumulative_returns <- cumprod(1 + returns)-1
replicated_cum <- cumprod(1+ replicated_etf_returns)-1
colnames(replicated_cum) <- "replicated_etf"

combined_cum <- merge(
  cumulative_returns,
  replicated_etf = replicated_cum,
  join = "inner"
)

# ETF vs Replicated ETF Plot

plot.zoo(cbind(combined_cum$EXS1.DE,combined_cum$replicated_etf),
         plot.type = "single",
         col = c("blue", "red"),
         lty = 1,
         lwd = 2,
         main = "ETF vs Replicated ETF (Cumulative Returns 2023-2025)",
         ylab = "Cumulative Return",
         xlab = "Timeline",
         cex.main = 0.9)
legend("topleft",
       legend = c("ETF", "Replicated ETF"),
       col = c("blue", "red"),
       lty = 1,
       lwd = 2)

abline(v = as.Date("2025-03-18"), col = "darkgreen", lty = 2, lwd = 2)
abline(v = as.Date("2025-03-31"), col = "purple", lty = 2, lwd = 2)
grid()


# Top10 Holdings vs ETF vs Replica Plot

holding_cols <- gray.colors(10, start = 0.7, end = 0.4)  
cols <- c(holding_cols, "blue", "red")  

ltys <- c(rep(1,10), 1, 1)  
lwds <- c(rep(1,10), 2, 2)  

plot.zoo(cbind(cumulative_returns[, top10_holdings$ticker],
               ETF = combined_cum$EXS1.DE,
               Replicated = combined_cum$replicated_etf),
         plot.type = "single",
         col = cols,
         lty = ltys,
         lwd = lwds,
         main = "Top 10 Holdings vs ETF vs Replicated ETF", 
         ylab = "Cumulative Returns",
         xlab = "Timeline")

legend("topleft",
       legend = colnames(plot_data),
       col = cols,
       lty = ltys,
       lwd = lwds,
       cex = 0.6)

############################################################
# End of Script
############################################################