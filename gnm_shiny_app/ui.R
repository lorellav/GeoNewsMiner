

# Definition of the user interface of the GeoNewsMiner app
#
# Developer: Kees van Eijden (k.vaneijden@uu.nl)
#

# MODALS: Functions for showing modal dialogs to users on the same page they are working ----
#
modal_data_values <-
  bs_modal(
    id =   "modal_data_values",
    title = h3("Frequencies"),
    body =  includeMarkdown("www/data_values.md"),
    size = "medium")

modal_cities <-
  bs_modal(
    id =   "modal_cities",
    title = h3("Cities"),
    body =  includeMarkdown("www/cities.md"),
    size = "medium")

modal_regions <-
  bs_modal(
    id =   "modal_regions",
    title = h3("Regions"),
    body =  includeMarkdown("www/regions.md"),
    size = "medium")

modal_percentile_cities <-
  bs_modal(
    id =   "modal_percentile_cities",
    title = h3("Show cities based on their frequencies"),
    body =  includeMarkdown("www/percentile_cities.md"),
    size = "medium")

modal_percentile_regions <-
  bs_modal(
    id =   "modal_percentile_regions",
    title = h3("Show Regions based on their frequencies"),
    body =  includeMarkdown("www/percentile_regions.md"),
    size = "medium")

modal_share <-
  bs_modal(
    id =   "modal_share",
    title = h3("Share your results"),
    body =  includeMarkdown("www/share.md"),
    size = "medium")

modal_overlay <- bs_modal(
    id =   "modal_overlay",
    title = h3("Historical Maps"),
    body =  includeMarkdown("www/overlay.md"),
    size = "medium")

modal_ToU <- bs_modal(
  id =     "modal_ToU", 
  title =   h3("Terms of Usage"),
  body =    includeMarkdown(path = "www/ToU.md"),
  footer =  tags$span(bs_modal_closebutton("Understood!")),    # user must accept ToU
  size =   "large")

# MAIN: User interface has a simple sidebar layout
# The main panel contains a few tabpanels for:
# 1. map to show data in a spatial context,
# 2. datatable of the data,
# 3. explanatory text and 
# 4. references for further reading
#
# The 'function(request)' bit is necessary to allow for sharing bookmarks between users
#
ui <- function(request) {
  
  fluidPage(
    
    # Application title
    #
    titlePanel("The GeoNewsMiner (GNM), 1898 - 1920"),
     
    # Functions displaying modal boxes to show usage info about an input widget
    modal_data_values,
    modal_cities,
    modal_percentile_cities,
    modal_regions,
    modal_percentile_regions,
    modal_share,
    modal_overlay,
    modal_ToU,
    
    # SIDEBAR ----  
    # Sidebar contains widgets for data selection and for display options 
    #
    sidebarLayout(
      sidebarPanel(
        
        # input widgets for selecting data are dynamically created by server, because the choices 
        # depend on data set being used
        #
        uiOutput(outputId = "selection_period"),            # selecting time period
        uiOutput(outputId = "selection_titles"),            # selecting newspaper titles
        
        # absolute values or percentages?
        #
        radioButtons("normalized",
                     label =        h4("Frequencies"), 
                     choiceNames =  c("Absolute", "Percentage"), 
                     choiceValues = c('no', 'yes'),
                     selected =     'no',
                     inline =       TRUE) %>% 
          shinyInput_label_embed(shiny_iconlink(name = 'info-circle') %>% bs_attach_modal(id_modal = "modal_data_values")),
        
        # show cities on map?
        #
        radioButtons("show_cities",
                      label =        h4("Cities"),
                      choiceNames =  c("Exclude", "Include"),
                      choiceValues = c(FALSE, TRUE),
                      selected =     FALSE,
                      inline =       TRUE) %>% 
          shinyInput_label_embed(shiny_iconlink(name = 'info-circle') %>%
                                   bs_attach_modal(id_modal = "modal_cities")),
        
        # which cities must be displayed: the most or least referenced?
        # 
        # the user only sees this widget when normalized is yes
        #
        conditionalPanel(
          condition = "input.show_cities == 'TRUE'",
          sliderInput(inputId = "perc_cities", 
                      label = h4("Percentile Range"),
                      min =   0,                   # only display cities above 10% percentile
                      max =   100,                  
                      value = c(0, 100),  # By default the TOP 10% is selected
                      step =  10) %>%
            shinyInput_label_embed(shiny_iconlink() %>% 
                                     bs_attach_modal(id_modal = "modal_percentile_cities"))),
        
        # idem regions
        #
        radioButtons("show_regions",
                     label =        h4("Regions"),
                     choiceNames =  c("Exclude", "Include"),
                     choiceValues = c(FALSE, TRUE),
                     selected =     FALSE,
                     inline =       TRUE) %>% 
          shinyInput_label_embed(shiny_iconlink(name = 'info-circle') %>% 
                                   bs_attach_modal(id_modal = "modal_regions")),
        
        conditionalPanel(
          condition = "input.show_regions == 'TRUE'",
          sliderInput(inputId = "perc_regions", 
                      label =   h4("Percentile Range"),
                      min =      0,               
                      max =      100,                  
                      value =    c(0, 100),  
                      step =     10) %>%
            shinyInput_label_embed(shiny_iconlink(name = 'info-circle') %>%
                                      bs_attach_modal(id_modal = "modal_percentile_regions"))),
        
        # User can opt for an overlay with a historical map (1880, 1914 or 1920)
        #
        radioButtons(inputId =      "hist_map",
                     label =        h4("Historical Maps"),
                     choiceNames =  c("1994", "1880", "1914", "1920"),
                     choiceValues = c("none", "world1880", "world1914", "world1920"),
                     selected =     "none",
                     inline =       TRUE) %>% 
         shinyInput_label_embed(shiny_iconlink(name = 'info-circle') %>% 
                                  bs_attach_modal(id_modal = "modal_overlay")),
        br(),
  
        # Bookmark save the current state of the app in an url which can be shared
        #
        bookmarkButton(label = "Share the results"),
        shiny_iconlink(name = 'info-circle') %>% 
          bs_attach_modal(id_modal = "modal_share")
      ),
 
      # MAIN ----
      # Contains 4 tabpanels for map, data table, explanation and references
      #
      mainPanel(
        tabsetPanel(
          id = "Map",
          tabPanel("Map",
                   leafletOutput("data_map", width = "100%", height = 500),
                   br(),
                   HTML("NA*: occurrences < 8"),
                   br(),
                   br(),
                   downloadButton("downloadMap", "Download Map")),
          tabPanel("Data",
                   DT::dataTableOutput("table_data", height = "700px"),
                   br(),
                   downloadButton("downloadData", "Download Data Selection")),
          tabPanel("About ...",
                   includeMarkdown(path = "www/about.md"),
                   
                   # User must accepts the gterms of usage
                   #
                   bs_button("Terms of Usage") %>%
                     bs_attach_modal(id_modal = "modal_ToU")
                   ),
          tabPanel("More ...",
                   includeMarkdown(path = "www/more.md")))
      ) # end of main panel ----
    ) # end of sidebarLayout
  ) # end of fluid page
} # end of ui function

