# Load necessary libraries
library(shiny)
library(dplyr)
library(ggplot2)
library(plotly)

# Define UI
ui <- fluidPage(
  titlePanel("Star Wars Data Explorer"),
  
  sidebarLayout(
    sidebarPanel(
      selectInput("Species", 
                  "Choose a Species:", 
                  choices = c("All", NULL))
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel("Characters", 
                 h3("Characters Table"),
                 p("Note: Height (cm) | Weight (kg)"),
                 tableOutput("character_table")),
        
        tabPanel("Height vs Weight", 
                 br(),
                 plotlyOutput("scatter_plot")),
        
        tabPanel("Statistical Tests", 
                 h3("Statistical Tests"),
                 verbatimTextOutput("chi_sq_result"),
                 p("Explanation: This test checks the relationship between gender and height category, weight category, etc.",
                   "If the p-value is below 0.05, we reject the null hypothesis, meaning a significant relationship exists."))
      )
    )
  )
)

# Define Server
server <- function(input, output, session) {
  
  # Clean and prepare the dataset
  complete_data <- reactive({
    starwars %>%
      mutate(sex = recode(sex, "male" = "Male", "female" = "Female", .default = "Other")) %>%
      filter(!is.na(sex), !is.na(height), !is.na(mass)) %>%
      mutate(
        Height_Category = cut(height, breaks = c(-Inf, 150, 170, 190, Inf), labels = c("Short", "Medium", "Tall", "Very Tall"), right = FALSE),
        Weight_Category = cut(mass, breaks = c(-Inf, 50, 75, 100, 150, Inf), labels = c("Underweight", "Normal", "Overweight", "Obese", "Very Obese"), right = FALSE)
      ) %>%
      rename(Species = species, Weight = mass, Height = height, Name = name, Sex = sex) %>%
      select(Name, Species, Sex, Height, Height_Category, Weight, Weight_Category)
  })
  
  # Update dropdown options
  observe({
    updateSelectInput(session, "Species", choices = c("All", unique(complete_data()$Species)))
  })
  
  # Filter data by species
  filtered_data <- reactive({
    if (input$Species == "All") complete_data() else complete_data() %>% filter(Species == input$Species)
  })
  
  # Render character table
  output$character_table <- renderTable({ filtered_data() })
  
  # Function to create the interactive plot with tooltip and regression line
  create_plot <- function(data) {
    # Check if there are fewer than 2 data points
    if (nrow(data) < 2) {
      # If fewer than 2 data points, just plot the points and avoid regression
      p <- ggplot(data, aes(x = Height, y = Weight)) +
        geom_point(aes(text = paste("Name:", Name, "<br>Height:", Height, " cm", "<br>Weight:", Weight, " kg")), 
                   color = "#007bff", size = 3, alpha = 0.7) +
        labs(title = paste("Height vs Weight for", input$Species),
             x = "Height (cm)", y = "Weight (kg)") +
        theme_minimal()
      
      plotly_p <- ggplotly(p, tooltip = "text")
      return(plotly_p)  # Return the plot without regression line or equation
    } else {
      # Fit linear model to get regression statistics
      model <- lm(Weight ~ Height, data = data)
      
      # Format the equation with better handling of negative signs
      equation <- paste("y = ", 
                        round(coef(model)[2], 2), "x", 
                        ifelse(coef(model)[1] < 0, paste(" - ", abs(round(coef(model)[1], 2))), 
                               paste(" + ", abs(round(coef(model)[1], 2)))),
                        sep = "")
      r_squared <- round(summary(model)$r.squared, 3)
      
      # Create the plot with regression line
      p <- ggplot(data, aes(x = Height, y = Weight)) +
        geom_point(aes(text = paste("Name:", Name, "<br>Height:", Height, " cm", "<br>Weight:", Weight, " kg")), 
                   color = "#007bff", size = 3, alpha = 0.7) + # "text" is only in geom_point
        geom_smooth(method = "lm", se = TRUE, fill = "grey80") + # Linear regression line with confidence interval
        labs(title = paste("Height vs Weight for", input$Species),
             x = "Height (cm)", y = "Weight (kg)") +
        theme_minimal()
      
      # Convert ggplot to plotly and add the equation and R-squared as annotations
      plotly_p <- ggplotly(p, tooltip = "text")
      
      # Add equation and R-squared value as annotations
      plotly_p <- plotly_p %>% layout(
        annotations = list(
          x = 0.5, y = 0.8, xref = "paper", yref = "paper",  # Adjusted y-value for space
          text = paste("Equation: ", equation, "<br>R² = ", r_squared),
          showarrow = FALSE,
          font = list(size = 14),
          align = "center"
        )
      )
      
      return(plotly_p)
    }
  }
  
  # Render the interactive plot
  output$scatter_plot <- renderPlotly({
    create_plot(filtered_data())
  })
  
  # Function for chi-squared tests
  run_chi_sq_test <- function(var1, var2, data) {
    tbl <- table(data[[var1]], data[[var2]])
    print(tbl)
    if (all(dim(tbl) > 1)) {
      tbl <- tbl + 0.5  # Handle empty cells
      chi_sq <- chisq.test(tbl)
      return(chi_sq)
    }
    return(NULL)
  }
  
  # Render chi-squared test results
  output$chi_sq_result <- renderPrint({
    data <- filtered_data()
    
    test_pairs <- list(
      c("Sex", "Height_Category"),
      c("Sex", "Weight_Category"),
      c("Height_Category", "Weight_Category")
    )
    
    test_names <- c("Sex vs Height Category", "Sex vs Weight Category", "Height Category vs Weight Category")
    
    for (i in seq_along(test_pairs)) {
      cat("Chi-Squared Test for", test_names[i], ":\n")
      result <- run_chi_sq_test(test_pairs[[i]][1], test_pairs[[i]][2], data)
      
      if (!is.null(result)) {
        print(result)
        cat(ifelse(result$p.value < 0.05, "Significant relationship found.", "No significant relationship."), "(p-value:", result$p.value, ")\n\n\n\n")
      } else {
        cat("Not enough data to run chi-squared test.\n\n\n\n")
      }
    }
  })
}

# Run the application
shinyApp(ui = ui, server = server)