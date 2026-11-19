# =============================================================================
# WEEK 05: SHARED PRESENTATION THEME
# =============================================================================
# ABSTRACT
# This helper standardizes every Week 5 ggplot using the projector-readable
# settings established in the Week 4 presentation charts. Source it before
# constructing a Week 5 visualization. It changes presentation styling only;
# it does not modify data, scales, calculations, or analytical results.

week05_presentation_theme <- function(legend_position = "bottom") {
  ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      legend.position = legend_position,
      panel.grid.minor = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(
        size = 16,
        face = "bold",
        hjust = 0.5
      ),
      plot.subtitle = ggplot2::element_text(
        size = 12,
        face = "plain",
        hjust = 0.5,
        margin = ggplot2::margin(b = 12)
      ),
      strip.text = ggplot2::element_text(
        size = 11.5,
        face = "bold"
      ),
      axis.text.x = ggplot2::element_text(
        size = 12,
        face = "bold"
      ),
      axis.text.y = ggplot2::element_text(
        size = 12,
        face = "bold"
      ),
      axis.title.x = ggplot2::element_text(
        size = 13.5,
        face = "bold",
        margin = ggplot2::margin(t = 12)
      ),
      axis.title.y = ggplot2::element_text(
        size = 13.5,
        face = "bold",
        margin = ggplot2::margin(r = 12)
      ),
      legend.text = ggplot2::element_text(size = 10.5),
      legend.title = ggplot2::element_text(size = 11, face = "bold"),
      plot.caption = ggplot2::element_text(
        size = 9.5,
        hjust = 0.5,
        margin = ggplot2::margin(t = 12)
      )
    )
}
