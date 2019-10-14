# Server logic for GeoNewsMiner for place names in the corpus of ChroniclItaly
#
server <- function(input, output, session) {
  
# Reading, cleansing, summarizing and tidying of data ------

  # Every row is an occurrence of a place name (location) in an article in an edition (date) of a newspaper (title)
  # 
  place_names_file <- "www/place_names.csv"
  place_names      <- readr::read_csv(place_names_file)
  place_names    %<>% dplyr::select(-date) %>% dplyr::rename(title = Title)
  
  # Every place name was fed into google geo code. The file geo_data contains for every 'location' the current (english)
  # name, the type of location ('city', 'country' or 'administartive area') and the coordinates of its center {lat, lon}
  #
  geo_data_file   <- "www/geo_data.csv"
  geo_data        <- readr::read_csv(geo_data_file)
  
  world1994        <- st_read(dsn= 'data/1994')
  world1920        <- st_read(dsn= 'data/1920')
  world1914        <- st_read(dsn= 'data/1914')
  world1880        <- st_read(dsn= 'data/1880')
  

  # currently the app uses the 1994 map from ?? archive as the base map
  #
  
  world         <- world1994
  st_crs(world) <- 4326
  world         %<>% rename(name_long = ABBREVNAME, iso_a2 = FIPS_CODE)
  
  # Add to each name occurrence the geo information (lat, lon)
  # The app treats the type of location differently, so we label these names with location type
  # country, region (administrative & colloquial area's)  and city names (loca. 
  # are supported
  #
  geo_data %<>%
    mutate(location_type = if_else(grepl("(?:^|\\+)locality(?:\\+|$)", location_type), "city", location_type)) %>%
    mutate(location_type = if_else(grepl("(?:^|\\+)country(?:\\+|$)", location_type), "country", location_type)) %>%
    mutate(location_type = if_else(grepl("(?:^|\\+)administrative_area_level_[12](?:\\+|$)", location_type),
                                   str_match(location_type, "(?:^|\\+)administrative_area_(level_[12])(?:\\+|$)")[,2], location_type)) %>%
    mutate(location_type = if_else(grepl("(?:^|\\+)colloquial_area(?:\\+|$)", location_type) &
                                   grepl("(?:^|\\+)political(?:\\+|$)", location_type), "colloquial", location_type)) %>%
    filter(location_type %in% c('country', 'city', 'level_1', 'level_2', 'level_3', 'level_4', 'colloquial'))
  
  # Use the google geocoding names of countries, cities (localities) and regions (administrative levels) to unify all
  # the different spellings of the same location
  #
  geo_data %<>% mutate(name_long = recode(location_type, country =  country,
                                                         city =     locality,
                                                         level_1 =  admin_1,
                                                         level_2 =  admin_2,
                                                         level_3 =  admin_2,
                                                         level_4 =  admin_2,
                                                         colloquial = colloquial_area)) %>%
    
    # No distinction in admin levels and colloquial area anymore. They are all regions
    #
                mutate(location_type = recode(location_type, country =    'country',
                                                             city =       'city',
                                                             level_1 =    'region',
                                                             level_2 =    'region',
                                                             level_3 =    'region',
                                                             level_4 =    'region',
                                                             colloquial = 'region'))

  
  # media_location_data <- geo_data %>%
  #   dplyr::inner_join(place_names, by = c("location" = "location")) %>%
  #   dplyr::filter(location_type == 'country' | location_type == 'city' | location_type == 'region') %>%
  #   dplyr::select(location, location_type, title, year, name_long, lat, lon, filename, freq)
  #  
  # 
  # Current world map does not have some small states
  # These nations will be discarded.
  #
  # media_location_data %<>% dplyr::filter(location_type %in% c('city', 'region') | 
  #                                  !location %in% c('vaticano', 'san marino', 'hongkong', 'monaco', 'malta', 'jersey'))
  # 
  
  # The center of the Philipines doesn't lie on it's territory but somewhere in the sea.
  # As a consequence the spatial joint with the world map wil not work for the Philippines.
  # We move the so called center of the Philippines to the center of its capital Manilla
  
  geo_data$lon[geo_data$country == "Philippines" & geo_data$location_type == "country"] <- 120.98422
  geo_data$lat[geo_data$country == "Philippines" & geo_data$location_type == "country"] <- 15.0
  
  # The titles of the media and the time periodes in which articles are published will be used 
  # as selection criteria. The input widgets in the app are dynamically created on the server side
  #
  np_titles <- unique(place_names$title)
  np_period <- c(min(place_names$year), max(place_names$year))
  
  # Some input values are not set during start up. To distuingish between values not known at start-up or other 
  # problems we need a logical which will be set to FALSE after initialisation stage.
  start_up  <- TRUE
  
  # Restoring from a bookmark doesn't go right automatically. 
  # Explicit restore of workflow is needed. Restore_map is a value to guide the process.
  #
  restore_map <- reactiveVal(value = "START")
  
  # The bounding box of the area that is visible on the map at start-up
  #
  lng1 <- -170.0
  lng2 <- +170.0
  lat1 <- -60.0
  lat2 <- +80.0
  # lng <-   12.56738
  # zoom <-  1
  
  output$selection_period <- renderUI({
    sliderInput(inputId = "years",
                label =    h4("Time Period"),
                min =      np_period[1],
                max =      np_period[2], 
                value =    np_period,
                ticks =    FALSE,
                sep =      "",
                step =     1,
                round =    TRUE)
  })
  
  output$selection_titles <- renderUI({
    checkboxGroupInput(inputId =  "checked_media",
                       label =     h4("Titles"), 
                       choices =   np_titles,
                       selected =  np_titles)
  })
  
  
  # Reactive function select_data() selects and summarizes the raw data according to the (changed) selection criteria.
  # This function is hyper reactive. Which means that the function immediately responds to a single user input activity.
  #
  select_data <- reactive({
    select_data       <- place_names
    if(!is.null(input$checked_media)) {
      checked_titles <- input$checked_media
    } else {
      if (start_up) {
        start_up <<- FALSE
        checked_titles <- np_titles 
      } else {
        checked_titles <- c("NO TITLES")
      }
    } 
    year_1         <- ifelse(is.null(input$years[1]), np_period[1], input$years[1])
    year_2         <- ifelse(is.null(input$years[2]), np_period[2], input$years[2])
    
    # User has changed his/her selection criteria. New (raw) data, please!
    #
    select_data %<>% filter(title %in% checked_titles)
    select_data %<>% filter(year >= year_1)
    select_data %<>% filter(year <= year_2)
    
    # Summarize data:
    # 1. number of different (front) pages in selection
    # 2. number of occurrences of place names in selection
    # Those numbers are needed when computing percentages
    #
    number_of_pages       <- as.integer(select_data %>% summarise(n_distinct(filename)))
    number_of_occurrences <- as.integer(select_data %>% summarise(sum(freq)))
    warning("TOTALS: ", number_of_pages, number_of_occurrences)
    
    # Joining selected data with geo data to get location type, current english spelling and coordinates (lon/lat)
    #
    select_data <- geo_data %>%
      dplyr::inner_join(select_data, by = c("location" = "location")) %>%
      dplyr::filter(location_type == 'country' | location_type == 'city' | location_type == 'region') %>%
      dplyr::select(location, location_type, title, year, name_long, lat, lon, filename, freq)
    
    # For each place name compute the number of (front) pages it is mentioned at least one time
    # and the total number of occurrences on all those pages
    # Also the number of distinct newspaper titles of all the front pages.
    #
    select_data %<>%
      dplyr::group_by(lon, lat, location_type, name_long) %>%
      dplyr::summarise(pages =  n_distinct(filename),
                       occurrences = sum(freq),
                       # begin_year = min(year),                  # not used anaymore
                       # end_year =   max(year),
                       n_titles =   n_distinct(title))
    
    # normalized data (aka percentages)
    #
    select_data %<>% ungroup() %>% mutate(pages_perc =    100 * pages / number_of_pages,
                                       occurrences_perc = 100 * occurrences / number_of_occurrences,
                                       n_titles_perc =    100 * n_titles / length(checked_titles))
    
    return(select_data)
  })
  
  # Helper function make_bins_abs creates bins to select fill colors for ranges of values
  #
  make_bins <- function(max_value, normalized = 'no') {
    
    # some constants demanded by color palette (should be parametrized)
    #
    min_bins <- 3
    max_bins <- 9
    
    legend_breaks   <- c(0, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, Inf)
    legend_breaks_norm <- c(0, 2, 4, 8, 15, 30, 60, 100)
    
    if (normalized != 'no') legend_breaks <- legend_breaks_norm
    
    upper         <- findInterval(x = max_value, legend_breaks, left.open = TRUE) + 1
    lower         <- ifelse(upper-max_bins+1 < 2, 2, upper-max_bins+1)
    b             <- append(legend_breaks[1], legend_breaks[lower:upper])
    if (length(b) < (min_bins+1)) {b <- legend_breaks[1:4]}
    return(b)
  }
  
  
  
  
  output$data_map <- renderLeaflet({
    
    # Draw the (base) map of the world
    #
    
    # reactive value restore_map guides the proces of drawing the maps when
    # user has used a bookmark
    #
    if ( restore_map() == "BASE_MAP") {
      restore_map("COUNTRY_MAP")
    }
    
    # layer id's are nec
    #
    layerIds = sprintf("w%g", 1:nrow(world))
    
    leaflet(world)  %>%
      flyToBounds(lng1 = lng1, lat1 = lat1, lng2 = lng2, lat2 = lat2) %>%
      
      # We use panes for maintaining a front to back hierarchy: cities, regions, historical borders, countries and world 
      #
      # World is needed to draw all the countries which aren't mentioned in the corpus
      #
      addMapPane(name = 'world', zIndex = 409) %>%
      addMapPane(name = 'countries', zIndex = 410) %>%
      addMapPane(name = 'hist_countries', zIndex = 411) %>%
      addMapPane(name = 'regions', zIndex = 415) %>%
      addMapPane(name = 'cities', zIndex = 420) %>%
      addPolygons(
        fillColor = "#808080",   # grey value also used for indicating NA value
        fillOpacity = 1,
        layerId =    layerIds,
        color =     "white",
        weight =    1,
        options =   leafletOptions(pane = 'world')
      )
  })
  
  map_bounds <- reactive({
    if (is.null(input$data_map_bounds)) {
      o <- list(west = -170, east = 170, south = -80, north = 80)
    } else {
      o <- list(west =  as.numeric(input$data_map_bounds$west),
                east =  as.numeric(input$data_map_bounds$east),
                south = as.numeric(input$data_map_bounds$south),
                north = as.numeric(input$data_map_bounds$north))
    }
    o
  })
  
  map_data <- reactive({

    ll_data    <- select_data()          # select_data is reactive and signals changes in data selection criteria (period and titles)
    normalized <- input$normalized       # signals whether users want to see absolute or normalized values
    
    if(nrow(ll_data) == 0) {
      return(NULL)
    }
    
    # Check if user want to see cities and if so in which percentile range
    #
    if (!as.logical(input$show_cities)) {
      ll_data %<>% filter(location_type != 'city')
    } else {
      above_below_index  <- as.integer(input$perc_cities / 10) + 1
      city_values        <- ll_data %>% filter(location_type == 'city') %>% pull(pages)
      above_below_values <- quantile(city_values, probs = seq(0, 1, 0.1))[above_below_index]
      
      ll_data %<>% filter(location_type %in% c('country', 'region') | (pages >= above_below_values[1] & 
                                                                       pages <= above_below_values[2]))
    }
    
    # idem for regions
    #
    if (!as.logical(input$show_regions)) {
      ll_data %<>% filter(location_type != 'region')
    } else {
      above_below_index  <- as.integer(input$perc_regions / 10) + 1
      region_values      <- ll_data %>% filter(location_type == 'region') %>% pull(pages)
      above_below_values <- quantile(region_values, probs = seq(0, 1, 0.1))[above_below_index]
      
      ll_data %<>% filter(location_type %in% c('country', 'city') | (pages >= above_below_values[1] & 
                                                                     pages <= above_below_values[2]))
    }
    # check if user want to see normalized data
    #
    if (normalized != 'no') {
      ll_data %<>% mutate(map_value = pages_perc)
    } else {
      ll_data %<>% mutate(map_value = pages)
    }
    
    # legend title
    #
    title <- switch(normalized,
               no =  "Number of pages",
               yes = "Percentage of pages")
               
    
    # Because we will use polygons for countries and circles for cities we apply color binning to show the value 
    # on the map. Continuous colors is more suitable for rasters.
    #
    bins    <- make_bins(max(ll_data$map_value, na.rm = TRUE), normalized = normalized)   # see make_bins()
    
    legends <- sprintf("%g - %g", bins[1:(length(bins)-1)] + 1, bins[2:length(bins)])         # legend label
    if (normalized == "no") {
      legends <- sprintf("%g - %g", bins[1:(length(bins)-1)] + 1, bins[2:length(bins)])
      legends[length(legends)] <- sprintf("%g +", bins[length(bins)-1]+1)
    } else {
      legends <- sprintf("%g - %g", bins[1:(length(bins)-1)], bins[2:length(bins)])
    }
    
    # The value will be mapped to a (fill) color for the polygons or circles. The map_value 
    # must be mapped to the index of its corresponding bin.
    #
    ll_data %<>% mutate(fill_value = ifelse(is.na(findInterval(map_value, bins, left.open = TRUE)),
                                            length(bins),
                                            findInterval(map_value, bins, left.open = TRUE)))
    
    map_colors <- brewer.pal(n = length(bins)-1, name =  "YlOrRd")
    map_colors <- append(map_colors, "#808080")
    legends    <- append(legends, "NA*")
    
    
    # recalculate the hove-over labels
    #
    switch(normalized, 
      yes      = {labels <-  sprintf("<strong>%s</strong><br/>%4.2f%% of pages<br/>%4.2f%% of occurrences</sup>",
                                    ll_data$name_long,
                                    ll_data$pages_perc,
                                    ll_data$occurrences_perc) %>% lapply(htmltools::HTML)},
      category = {labels <-  sprintf("<strong>%s</strong><br/>%4.2f%% of pages</sup>",
                                     ll_data$name_long,
                                     ll_data$pages_perc_category) %>% lapply(htmltools::HTML)},
      no =       {labels <-  sprintf("<strong>%s</strong><br/>%g pages<br/>%g occurrences<br/>%g titles</sup>",  # period deleted <br/>from %g till %g
                                      ll_data$name_long,
                                      ll_data$map_value,
                                      ll_data$occurrences,
                                      ll_data$n_titles            # period deleted ,ll_data$begin_year, ll_data$end_year
                                     ) %>% lapply(htmltools::HTML)})
    
    ll_data$labels <- labels
    
    r <- list(data =       ll_data,
              normalized = normalized,
              bins =       bins, 
              labels =     labels, title = title, legends = legends, 
              map_colors = map_colors)
  })
  
  country_map_data <- reactive({
    # observe changes in country map data and adjust the map accordingly 
    # Zooming and/or scrolling aren't considered as changes in the map data
    #
    country_map <- map_data()
    if (is.null(country_map)) {
      return(NULL)
    }
    
    country_map$data %<>% filter(location_type == 'country')
    if (nrow(country_map$data) == 0) {
      return(NULL)
    }
    
    # 
    # #Locations and its attributes are linked to geometries (MULTIPOLYGONS) describing the 
    # # the territory of a country on the worldmap.
    # # First transform (lon,lat) to POINT geometries and then do a spatial join with the territories (MULTI Polygons)
    # #
    # 
    # 
    country_map$data %<>% st_as_sf(coords = c("lon", "lat"), crs = 4326, agr = "constant")
    # 
    country_map$data <- st_join(world[c("iso_a2")],
                                country_map$data[c("pages", "name_long", "n_titles",
                                                   # "begin_year", "end_year",
                                                   "pages_perc", "n_titles_perc", "fill_value",
                                                   "map_value", "labels")],
                                left = FALSE)
    return(country_map)
  })
  
  
  observe({
    new_map <- country_map_data()
    if (restore_map() == "COUNTRY_MAP") {
      restore_map("HIST_MAP")
    }
    
    if (is.null(new_map)) {
      leafletProxy("data_map")  %>%
        clearGroup(group = 'countries') %>%
        removeControl(layerId = 'legend1')
    } else {
      leafletProxy("data_map", data = new_map$data)  %>%
        clearGroup(group = 'countries') %>%
        addPolygons(fillColor =        ~new_map$map_colors[fill_value],
                    #layerId =           polyIds,
                    weight =            1,
                    opacity =           1,
                    color =            "white",
                    fillOpacity =       1,
                    group =            'countries',
                    options =           leafletOptions(pane = 'countries'),
                    highlightOptions  = highlightOptions(weight =       1,
                                                         color =       'black',
                                                         fillOpacity =  0.7,
                                                         bringToFront = TRUE),
                    label =            ~labels,
                    labelOptions =      labelOptions(style =      list("font-weight" = "normal"),
                                                     textsize =  "10px",
                                                     direction = "auto")) %>%
        addLegend(
          colors =    new_map$map_colors,
          layerId =  "legend1",
          group =     'countries',
          values =   ~fill_value,
          labels =    new_map$legends,
          opacity =   0.7,
          title =     new_map$title,
          position = "bottomleft")}
  })
  
  observe({
    #
    # observe if the user wants to see the cities on the map or not
    #
    if (is.null(input$show_cities) || isFALSE(input$show_cities)) {
      leafletProxy("data_map") %>%
        hideGroup(group = 'cities')
    } else {
      leafletProxy("data_map") %>%
        showGroup(group = 'cities')
    }
  })
  
  observe({
    #
    # observe if the user wants to see the regions on the map or not
    #
    if (is.null(input$show_regions) || isFALSE(input$show_regions)) {
      leafletProxy("data_map") %>%
        hideGroup(group = 'regions')
    } else {
      leafletProxy("data_map") %>%
        showGroup(group = 'regions')
    }
  })
    #   
    # Observe if the user wants to overlay base map with a historical map
  observe({
    if (restore_map() == "HIST_MAP") {
      restore_map("REGION_MAP")
    }
    if (input$hist_map == 'none') {
      leafletProxy("data_map") %>% clearGroup(group = "hist_countries")
    } else {
      hist_map <- eval(parse(text = input$hist_map))
      leafletProxy("data_map", data = hist_map)  %>%
      clearGroup(group = 'hist_countries') %>%
      addPolygons(fillColor =        "white",
                  weight =            2,
                  opacity =           0.5,
                  color =            "black",
                  dashArray =        c(3,6),
                  fillOpacity =       0,
                  group =            'hist_countries',
                  options =           leafletOptions(pane = 'hist_countries'),
                  label =            ~ABBREVNAME)}
  })
  
  location_map_data <- reactive({
    # Observe if map data for cities has changed and adjust cities on map accordingly.
    # 
    new_map <- map_data()
    if (is.null(new_map)) {
      return(NULL)
    }
    new_map$data %<>% filter(location_type %in% c('city', 'region'))
    if (nrow(new_map$data) == 0) {
      return(NULL)
    }
    # 
    # Create sf table (geom = POINT) for ggplot and
    # add XandY coordinates for leaflet
    #
    new_map$data %<>% st_as_sf(coords = c("lon", "lat"), crs = 4326, agr = "constant")
    new_map$data %<>% cbind(st_coordinates(new_map$data))
    return(new_map)
  })
  
  observe({
    new_map        <- location_map_data()
    
    if(restore_map() == "REGION_MAP") {
      restore_map("CITY_MAP")
    }
    
    if (is.null(new_map)) {
      leafletProxy("data_map")  %>%
        clearGroup(group = 'regions')
    } else {
      new_map$data %<>% as_tibble() %>% filter(location_type == 'region')
      if(nrow(new_map$data) == 0) {
        leafletProxy("data_map", data = new_map$data)  %>%
          clearGroup(group = 'regions')
      } else {
        leafletProxy("data_map", data = new_map$data) %>%
          clearGroup(group = 'regions') %>%
          addRectangles(lng1 =    ~(X - fill_value/10),
                        lat1 =    ~(Y - fill_value/15),
                        lng2 =    ~(X + fill_value/10),
                        lat2 =    ~(Y + fill_value/15),
                     #radius = ~5000*fill_value,  # keeps cities with few citations visible
                     color =  '#808080',
                     fillColor =  ~new_map$map_colors[fill_value],
                     fillOpacity = 1,
                     weight =  2,
                     opacity = 1,
                     group =  'regions',                           # group value will be used for clearing and hiding
                     options = leafletOptions(pane = 'regions'),  # panes are used to keep cities on top of countries
                     label =   ~labels,
                     highlightOptions  = highlightOptions(weight =       1,
                                                          color =       'black',
                                                          fillOpacity =  0.8,
                                                          bringToFront = TRUE))
      }
    }
  })
  
  
  city_map_data <- reactive({
    # Observe if map data for cities has changed and adjust cities on map accordingly.
    # 
    new_map <- map_data()
    if (is.null(new_map)) {
      return(NULL)
    }
    new_map$data %<>% filter(location_type == 'city')
    if (nrow(new_map$data) == 0) {
      return(NULL)
    }
    
    # 
    # Create sf table (geom = POINT) for ggplot and
    # add XandY coordinates for leaflet
    #
    new_map$data %<>% st_as_sf(coords = c("lon", "lat"), crs = 4326, agr = "constant")    # sf table
    new_map$data %<>% cbind(st_coordinates(new_map$data))                                 # adds X and Y (lon,lat) columns
    return(new_map)
  })
  
  
  observe({
    new_map        <- location_map_data()
    new_map$data %<>% as_tibble()
    
    if(restore_map() == "CITY_MAP") {
      restore_map("RESTORE_END")
    }
    
    if (is.null(new_map)) {
      leafletProxy("data_map")  %>%
        clearGroup(group = 'cities')
    } else {
      new_map$data %<>% as_tibble() %>% filter(location_type == 'city')
      if(nrow(new_map$data) == 0) {
        leafletProxy("data_map", data = new_map$data)  %>%
          clearGroup(group = 'cities')
      } else {
        leafletProxy("data_map", data = new_map$data) %>%
          clearGroup(group = 'cities') %>%
          addCircles(lng =    ~X,
                     lat =    ~Y,
                     radius = ~5000*fill_value,  # keeps cities with few citations visible
                     color =  '#808080',
                     fillColor =  ~new_map$map_colors[fill_value],
                     fillOpacity = 1,
                     weight =  2,
                     opacity = 1,
                     group =  'cities',                           # group value will be used for clearing and hiding
                     options = leafletOptions(pane = 'cities'),  # panes are used to keep cities on top of countries
                     label =   ~labels,
                     highlightOptions  = highlightOptions(weight =       1,
                                                          color =       'black',
                                                          fillOpacity =  0.8,
                                                          bringToFront = TRUE))
      }
    }
  })
  
# Downloadable ggplot map --------
  
  # A ggplot copy of the leaflet map as is displayed ast the moment.
  # A mapshot of Leaflet map doen't work because of leafletProxy
  #
  download_map <- reactive({
    
    # Observe change in bounding box (bb) of map on the screen
    #
    bb <- map_bounds()
    
    # Crop ggplot's version of the world to the boundings of the map on the display
    #
    plot_world   <- sf::st_crop(x = world,
                                xmin = bb$west,  xmax = bb$east,
                                ymin = bb$south, ymax = bb$north)
    plot_world   <- sf::st_transform(plot_world, "+init=epsg:3857")     # 3857 is leaflet's default crs
    
    p <- ggplot2::ggplot() + 
      ggplot2::geom_sf(data =    plot_world,
                       mapping = aes(geometry = geometry), 
                       size =    0.3, 
                       fill =   "#808080", # color for NA value in leaflet map
                       color =  "white")
    
    # Observe change in map values and adjust ggplot map accordingly
    #
    new_country_map <- country_map_data()
    if (!is.null(new_country_map)) {
      plot_data   <- sf::st_crop(x =    new_country_map$data,
                                 xmin = bb$west,  xmax = bb$east,
                                 ymin = bb$south, ymax = bb$north)
      
      # Plot the iso_a2 name of countries in the center of each country
      #
      #plot_labels <- sf::st_centroid(plot_data, of_largest_polygon = TRUE) %>% select(name = iso_a2)
      #plot_labels$name[is.na(plot_labels$name)] <- ""  # of some countries iso_a2 is missing
      
      # reproject the shapes and points with the crs used by leaflet (3857)
      #
      plot_data   <- sf::st_transform(plot_data, "+init=epsg:3857")
      #plot_labels <- sf::st_transform(plot_labels, "+init=epsg:3857")
      
      # Add the countries to the ggplot map
      p <- p +
        ggplot2::geom_sf(data =    plot_data,
                         mapping = aes(geometry = geometry,
                                      fill =     factor(fill_value, levels = 1:length(new_country_map$bins))),
                         color =  'white',
                         size  =   0.3) +
        # ggplot2::geom_sf_text(data =    plot_labels,
        #                       mapping = aes(geometry = geom, label = name),
        #                       size =    2)  +
        ggplot2::scale_fill_manual(values = new_country_map$map_colors,
                                   labels = new_country_map$legends,
                                   name =   new_country_map$title,
                                   drop =   FALSE)                  # show all labels even if not used in the map
    }
    
    if (!is.null(input$hist_map) && input$hist_map != 'none') {
      hist_map <- eval(parse(text = input$hist_map))
      
      st_crs(hist_map) <- 4326
      hist_map   <- sf::st_crop(x =    hist_map,
                                xmin = bb$west,  xmax = bb$east,
                                ymin = bb$south, ymax = bb$north)
      hist_map <- sf::st_transform(hist_map, "+init=epsg:3857")
      p <- p + ggplot2::geom_sf(data =    hist_map,
                                mapping = aes(geometry = geometry),
                         fill =   'white',
                         alpha =   0,
                         color =  'black',
                         size  =   0.3)
    }
  
    # Observe change in city or region map values for and adjust ggplot map accordingly
    #
    new_location_map <- location_map_data() 
    if (!is.null(new_location_map)) {
      
      # crop to the boundings of map on the screen
      #
      plot_data   <- sf::st_crop(x =    new_location_map$data,
                                 xmin = bb$west,  xmax = bb$east,
                                 ymin = bb$south, ymax = bb$north)
      
      # To ensure the printed map has the same appearance as the map on the screen,
      # reproject the shapes to the crs used by leaflet (3857)
      #
      plot_data   <- sf::st_transform(plot_data, "+init=epsg:3857")
      plot_data  %<>% select(-X, -Y) %>% cbind(st_coordinates(plot_data)) # the old X and Y were in the wrong CRS
      
      # Add regions as squares to the map.
      # The fill color indicates the number of articles in which the name of the city occurs. See legend!
      # Also the width/height gives an indication of the number of occurrences
      #
      plot_region <- plot_data %>% filter(location_type == 'region')
      p <- p + geom_tile(data =    plot_region,
                         mapping = aes(x =      X,
                                       y =      Y,
                                       width =  fill_value * 20000,
                                       height = fill_value * 20000,
                                       fill =   factor(fill_value, levels = 1:length(new_location_map$bins))),
                            colour =  "#808080")
      
      # Add cities as circles to the map.
      # The fill color indicates the number of articles in which the name of the city occurs. See legend!
      # Also the radius gives an indication of the number of occurrences
      #
      plot_city <- plot_data %>% filter(location_type == 'city')
      p <- p +
        ggforce::geom_circle(data =    plot_city,
                             mapping = aes(x0 =   X,
                                           y0 =   Y,
                                           r =    fill_value * 5000,
                                           fill = factor(fill_value, levels = 1:length(new_location_map$bins))),
                             colour =  "#808080")
    }
    
    p <- p +
      coord_sf(label_axes = "----") +                 # suppress the graticules (meridians/parallels)
      xlab("") + ylab("") + ggtitle("The GeoNewsMiner (GNM), 1898 - 1920")
    return(p)
  })
  
  output$downloadMap <- downloadHandler(
    filename = function(){paste("map",'.png',sep='')},
    content =  function(file){ggsave(file, plot = download_map())}
  )
  
# Panel data section -----
  output$table_data <- renderDataTable({
    data <- select_data()
    data %<>% select(-lon, -lat, -n_titles_perc)
    data %<>% rename(
                type =        location_type,
                name =        name_long,
                pages =   pages,
                '% pages' =    pages_perc,
                occurrences =  occurrences,
                '% occs' =    occurrences_perc,
                titles =      n_titles)
               # 'first year' = begin_year,
               # 'last year'=   end_year)
    DT::datatable(data = data,
                  colnames = c('type' =        'type',
                               'name' =        'name',
                               'pages' =       'pages',
                               '% pages' =      '% pages',
                               'occurrences' = 'occurrences',
                               '% occs' =      '% occs',
                               'titles' =      'titles'),
                               # 'first year'=   'first year',
                               # 'last year'=    'last year'),
                  fillContainer = TRUE) %>%
      formatRound(c('% pages', '% occs'), 2)
  })
  
  output$downloadData <- downloadHandler(
    filename = function() {
      paste("place_names", ".csv", sep = "")
    },
    content = function(file) {
      data <- select_data()
      data %<>% select(-lon, -lat, -n_titles_perc)
      data %<>% rename(
        type =         location_type,
        name =         name_long,
        pages =        pages,
        '% pages' =    pages_perc,
        occurrences =  occurrences,
        '% occs' =     occurrences_perc,
        titles =       n_titles)
        # 'first year' = begin_year,
        # 'last year'=   end_year)

      write_csv(data, file)
    }
  )
  
# Bookmark section -----------
  
  # To keep the url short, exclude state variables which will not be used on restore. 
  #
  setBookmarkExclude(c("table_data_rows_current",
                       "table_data_cell_clicked",
                       "table_data_search", 
                       "table_data_rows_selected", 
                       "table_data_rows_all", 
                       "table_data_state",
                       "data_map_center",
                       "data_map_groups",
                       "data_map_zoom",
                       "data_map_shape_mouseover",
                       "data_map_shape_mouseout"))
  
  onBookmark(function(state) {
     
    # Leaflet doesn't restore view point and zoom level from the saved state variables.
    # These values are saved and are explicitely set when restoring the app
    #
    state$values$zoom     <- isolate(input$data_map_zoom)
    state$values$center   <- isolate(input$data_map_center) # {lat, lng}
    state$values$bounds   <- isolate(input$data_map_bounds)
    
    # when restoring program must know which panel was active during bookmarking
    #
    state$values$tabpanel <- isolate(input$Map)             
  }) 

  
  onRestore(function(state) {
    
    # 
    #
    if ( restore_map() == "START") {
        
      lat1 <<- state$values$bounds$south
      lat2 <<- state$values$bounds$north
      lng1 <<- state$values$bounds$west
      lng2 <<- state$values$bounds$east
      
      # If a bookmark is made while the data panel is selected, the map will not be
      # restored unless explicitely triggered by reactive value restore_map
      #
      if (state$values$tabpanel == "Data") {
        restore_map("BASE_MAP")   # base map triggers countries and countries triggers regions and so on
      }
    }
  })
  # End of bookmark section -------
  
} # end of server function -----

# Run the application ---> moved to global.R
# shinyApp(ui = ui, server = server, enableBookmarking = "url")

