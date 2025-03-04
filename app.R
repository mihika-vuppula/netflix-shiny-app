library(shiny)
library(leaflet)
library(ggplot2)
library(dplyr)
library(plotly)
library(DT)
library(rsconnect)


# Load and prepare the dataset
netflix_data <- read.csv("https://raw.githubusercontent.com/mihika-vuppula/netflix-shiny-app/refs/heads/main/Netflix_Userbase.csv")

# Convert to date columns
netflix_data$Join.Date <- as.Date(netflix_data$Join.Date, format = "%d-%m-%y")
netflix_data$Last.Payment.Date <- as.Date(netflix_data$Last.Payment.Date, format = "%d-%m-%y")

# Country coordinates
country_coords <- data.frame(
  Country = c("United States", "Spain", "Canada", "United Kingdom", "Australia", "Germany", "France", "Brazil", "Mexico", "Italy"),
  lat = c(37.0902, 40.4637, 56.1304, 55.3781, -25.2744, 51.1657, 46.6034, -14.2350, 23.6345, 41.8719),
  lon = c(-95.7129, -3.7492, -106.3468, -3.4360, 133.7751, 10.4515, 2.2137, -51.9253, -102.5528, 12.5674)
)

# Join coordinates into the dataset
netflix_data <- merge(netflix_data, country_coords, by = "Country")

# Group age groups
netflix_data <- netflix_data %>%
  mutate(Age.Group = case_when(
    Age >= 25 & Age <= 35 ~ "25-35",
    Age >= 36 & Age <= 45 ~ "36-45",
    Age >= 46 & Age <= 60 ~ "46-60",
    TRUE ~ "Other"
  ))

# Calculate subscription duration in days
netflix_data <- netflix_data %>%
  mutate(Subscription.Duration = as.numeric(Last.Payment.Date - Join.Date))

# Functions for externalizing complex logic
get_filtered_data <- function(data, subscription_type, bounds) {
  latRng <- range(bounds$north, bounds$south)
  lonRng <- range(bounds$east, bounds$west)
  
  data %>%
    filter(lat >= latRng[1], lat <= latRng[2], lon >= lonRng[1], lon <= lonRng[2]) %>%
    filter((subscription_type == "All") | Subscription.Type == subscription_type)
}

generate_bar_chart <- function(data, clicked_country) {
  country_bar_data <- data %>%
    filter(Country == clicked_country) %>%
    group_by(Subscription.Type) %>%
    summarise(TotalRevenue = sum(Monthly.Revenue))
  
  plot_ly(country_bar_data, x = ~Subscription.Type, y = ~TotalRevenue, type = 'bar',
          marker = list(color = 'rgba(229, 9, 20, 0.7)')) %>%
    layout(title = paste0("<span style='color:red;'>", clicked_country, "</span> Revenue Breakdown"),
           xaxis = list(title = "Subscription Type"),
           yaxis = list(title = "Total Revenue"),
           paper_bgcolor = 'rgba(0, 0, 0, 1)', 
           plot_bgcolor = 'rgba(0, 0, 0, 1)',    
           font = list(color = 'white'), 
           margin = list(l = 40, r = 40, t = 50, b = 40)) %>%
    config(displayModeBar = FALSE)  
}

generate_pie_chart <- function(filtered_data) {
  device_data <- filtered_data %>%
    group_by(Device) %>%
    summarise(Count = n())
  
  plot_ly(device_data, labels = ~Device, values = ~Count, type = 'pie',
          marker = list(colors = c('rgba(138, 17, 10, 0.7)', 
                                   'rgba(236, 6, 10, 0.7)', 
                                   'rgba(229, 9, 20, 1)', 
                                   'rgba(128, 128, 128, 1)', 
                                   'rgba(200, 0, 0, 0.7)')), 
          textinfo = 'label+percent', insidetextfont = list(color = '#FFFFFF'),
          hoverinfo = 'none') %>%
    layout(title = list(text = "Device Preference by Age and Gender", y = 0.98),
           showlegend = TRUE,
           paper_bgcolor = 'rgba(0, 0, 0, 1)',
           plot_bgcolor = 'rgba(0, 0, 0, 1)',
           font = list(color = '#FFFFFF'))
}

# UI layout with context annotations
ui <- fluidPage(
  titlePanel("Netflix User Analysis App"),
  
  p("This app provides insights into Netflix user data, such as revenue by country, device preferences, and subscription durations. Use the filters to explore the data and understand different aspects of user behavior."),
  
  # Visualization 1: Map and bar chart
  fluidRow(column(12, selectInput("subscription_type", "Subscription Type",
                                  choices = c("All", "Basic", "Standard", "Premium"), selected = "All"),
                  p("Use the above dropdown to filter the data by subscription type and the countries.Click on a country to see its revenue breakdown in the bar graph on the right"))),
  
  fluidRow(
    column(6, leafletOutput("mapOutput")),
    column(6, plotlyOutput("countryBar"))
  ),
  br(), br(),
  
  # Visualization 2: Filter for Age Group and Gender in pie chart
  fluidRow(
    column(6, selectInput("age_group", "Select Age Group",
                          choices = c("25-35", "36-45", "46-60"), selected = "25-35"),
           p("Select an age group to see device usage preferences.")),
    column(6, selectInput("gender", "Select Gender",
                          choices = unique(netflix_data$Gender), selected = "Female"),
           p("Select a gender to refine the device preference data."))
  ),
  fluidRow(column(12, plotlyOutput("devicePieChart"))),
  br(), br(),
  
  # Visualization 3: Filtered Data Table for Subscription Duration
  fluidRow(column(12, DTOutput("filteredTable"))),
  p("The table below shows the filtered subscription duration based on subscription type, selected age and gender filters.")
)

# Server logic
server <- function(input, output, session) {
  
  # Reactive expression for filtered data based on map bounds and subscription type
  filtered_data <- reactive({
    get_filtered_data(netflix_data, input$subscription_type, input$mapOutput_bounds)
  })
  
  filtered_device_data <- reactive({
    netflix_data %>%
      filter(Age.Group == input$age_group & Gender == input$gender)
  })
  
  # Reactive expression for filtered table data based on subscription type, age, and gender
  filtered_table_data <- reactive({
    netflix_data %>%
      filter((input$subscription_type == "All") | Subscription.Type == input$subscription_type) %>%
      filter(Age.Group == input$age_group & Gender == input$gender)
  })
  
  # Render leaflet map
  output$mapOutput <- renderLeaflet({
    leaflet(options = leafletOptions()) %>%
      addProviderTiles(providers$CartoDB.DarkMatter) %>%
      setView(lng = -30, lat = 20, zoom = 2)
  })
  
  # Observe map bounds and filter data
  observe({
    country_data <- netflix_data %>%
      filter((input$subscription_type == "All") | Subscription.Type == input$subscription_type) %>%
      group_by(Country, lat, lon) %>%
      summarise(TotalRevenue = sum(Monthly.Revenue))
    
    leafletProxy("mapOutput", data = country_data) %>%
      clearMarkers() %>%
      addCircles(lng = ~lon, lat = ~lat, weight = 1, radius = 100000,
                 color = "red", fillOpacity = 0.8, layerId = ~Country)
  })
  
  observeEvent(input$mapOutput_shape_click, {
    click <- input$mapOutput_shape_click
    if (is.null(click)) return()
    
    clicked_country_data <- filtered_data() %>%
      filter(lat == click$lat & lon == click$lng) %>%
      select(Country) %>%
      distinct()
    
    clicked_country <- clicked_country_data$Country
    
    total_revenue <- filtered_data() %>%
      filter(Country == clicked_country) %>%
      summarise(TotalRevenue = sum(Monthly.Revenue)) %>%
      .$TotalRevenue
    
    leafletProxy("mapOutput") %>%
      addPopups(lng = click$lng, lat = click$lat, 
                popup = paste0("<strong>Country: </strong>", clicked_country, "<br>",
                               "<strong>Revenue : </strong>$", format(total_revenue, big.mark = ",")))
    
    output$countryBar <- renderPlotly({
      generate_bar_chart(netflix_data, clicked_country)
    })
  })
  
  output$devicePieChart <- renderPlotly({
    generate_pie_chart(filtered_device_data())
  })
  
  # Filtered data table
  output$filteredTable <- renderDT({
    filtered_table_data() %>%
      select(User.ID, Subscription.Type, Subscription.Duration, Gender, Age.Group) %>%
      datatable(options = list(pageLength = 5, autoWidth = TRUE))
  })
}

shinyApp(ui = ui, server = server)