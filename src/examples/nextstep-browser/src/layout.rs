// Layout Engine for NeXTSTEP Browser
// Implements CSS box model with NeXT's advanced typography

use crate::html_parser::{HTMLElement, HTMLNode};
use crate::css_parser::{ComputedStyle, DisplayType, BoxModel, Length};

#[derive(Debug, Clone)]
pub struct LayoutEngine {
    viewport_width: f32,
    viewport_height: f32,
    font_metrics: FontMetricsCache,
}

#[derive(Debug, Clone)]
pub struct LayoutBox {
    pub rect: Rect,
    pub style: ComputedStyle,
    pub children: Vec<LayoutBox>,
    pub content: LayoutContent,
}

#[derive(Debug, Clone)]
pub enum LayoutContent {
    Element(HTMLElement),
    Text(String),
}

#[derive(Debug, Clone, Copy)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

#[derive(Debug, Clone)]
pub struct FontMetricsCache {
    metrics: std::collections::HashMap<String, FontMetrics>,
}

#[derive(Debug, Clone)]
pub struct FontMetrics {
    pub ascent: f32,
    pub descent: f32,
    pub line_height: f32,
    pub average_char_width: f32,
}

impl LayoutEngine {
    pub fn new(viewport_width: f32, viewport_height: f32) -> Self {
        LayoutEngine {
            viewport_width,
            viewport_height,
            font_metrics: FontMetricsCache::new(),
        }
    }
    
    pub fn compute_layout(&mut self, root: &HTMLElement) -> LayoutBox {
        let viewport = Rect {
            x: 0.0,
            y: 0.0,
            width: self.viewport_width,
            height: self.viewport_height,
        };
        
        self.layout_element(root, viewport, None)
    }
    
    fn layout_element(&mut self, element: &HTMLElement, containing_block: Rect, 
                     parent_style: Option<&ComputedStyle>) -> LayoutBox {
        // Inherit or compute style
        let style = self.compute_element_style(element, parent_style);
        
        match style.display {
            DisplayType::None => {
                // Don't layout elements with display: none
                LayoutBox {
                    rect: Rect { x: 0.0, y: 0.0, width: 0.0, height: 0.0 },
                    style,
                    children: vec![],
                    content: LayoutContent::Element(element.clone()),
                }
            }
            DisplayType::Block => self.layout_block(element, containing_block, style),
            DisplayType::Inline => self.layout_inline(element, containing_block, style),
            DisplayType::InlineBlock => self.layout_inline_block(element, containing_block, style),
            _ => self.layout_block(element, containing_block, style), // Default to block
        }
    }
    
    fn layout_block(&mut self, element: &HTMLElement, containing_block: Rect, 
                   style: ComputedStyle) -> LayoutBox {
        // Calculate dimensions
        let margin = &style.margin;
        let border = &style.border;
        let padding = &style.padding;
        
        // Width calculation
        let content_width = match &style.width {
            Some(Length::Px(w)) => *w,
            Some(Length::Percent(p)) => containing_block.width * (p / 100.0),
            _ => containing_block.width - margin.left - margin.right 
                 - border.width * 2.0 - padding.left - padding.right,
        };
        
        // X position
        let x = containing_block.x + margin.left + border.width + padding.left;
        
        // Layout children
        let mut y = containing_block.y + margin.top + border.width + padding.top;
        let mut children_layout = Vec::new();
        let mut content_height = 0.0;
        
        for child in &element.children {
            match child {
                HTMLNode::Element(child_elem) => {
                    let child_containing_block = Rect {
                        x,
                        y,
                        width: content_width,
                        height: containing_block.height - (y - containing_block.y),
                    };
                    
                    let child_box = self.layout_element(child_elem, child_containing_block, Some(&style));
                    y += child_box.rect.height;
                    content_height += child_box.rect.height;
                    children_layout.push(child_box);
                }
                HTMLNode::Text(text) => {
                    if !text.trim().is_empty() {
                        let text_box = self.layout_text(text, content_width, &style);
                        y += text_box.rect.height;
                        content_height += text_box.rect.height;
                        children_layout.push(text_box);
                    }
                }
                HTMLNode::Comment(_) => {} // Skip comments
            }
        }
        
        // Height calculation
        let height = match &style.height {
            Some(Length::Px(h)) => *h,
            Some(Length::Percent(p)) => containing_block.height * (p / 100.0),
            _ => content_height,
        } + margin.top + margin.bottom + border.width * 2.0 + padding.top + padding.bottom;
        
        LayoutBox {
            rect: Rect {
                x: containing_block.x + margin.left,
                y: containing_block.y + margin.top,
                width: content_width + padding.left + padding.right + border.width * 2.0,
                height,
            },
            style,
            children: children_layout,
            content: LayoutContent::Element(element.clone()),
        }
    }
    
    fn layout_inline(&mut self, element: &HTMLElement, containing_block: Rect, 
                    style: ComputedStyle) -> LayoutBox {
        // Simplified inline layout - treat as block for now
        // Real implementation would handle line boxes and text flow
        self.layout_block(element, containing_block, style)
    }
    
    fn layout_inline_block(&mut self, element: &HTMLElement, containing_block: Rect, 
                          style: ComputedStyle) -> LayoutBox {
        // Simplified inline-block - treat as block
        self.layout_block(element, containing_block, style)
    }
    
    fn layout_text(&mut self, text: &str, max_width: f32, style: &ComputedStyle) -> LayoutBox {
        let font_key = format!("{}-{}", style.font_family[0], style.font_size);
        let metrics = self.font_metrics.get_or_compute(&font_key, style);
        
        // Simple text layout - wrap at word boundaries
        let words: Vec<&str> = text.split_whitespace().collect();
        let space_width = metrics.average_char_width * 0.5; // Approximate
        
        let mut lines = Vec::new();
        let mut current_line = String::new();
        let mut current_width = 0.0;
        
        for word in words {
            let word_width = word.len() as f32 * metrics.average_char_width;
            
            if current_width + word_width > max_width && !current_line.is_empty() {
                lines.push(current_line.trim().to_string());
                current_line = String::new();
                current_width = 0.0;
            }
            
            if !current_line.is_empty() {
                current_line.push(' ');
                current_width += space_width;
            }
            
            current_line.push_str(word);
            current_width += word_width;
        }
        
        if !current_line.is_empty() {
            lines.push(current_line.trim().to_string());
        }
        
        let height = lines.len() as f32 * metrics.line_height;
        let final_text = lines.join("\n");
        
        LayoutBox {
            rect: Rect {
                x: 0.0, // Will be positioned by parent
                y: 0.0,
                width: max_width,
                height,
            },
            style: style.clone(),
            children: vec![],
            content: LayoutContent::Text(final_text),
        }
    }
    
    fn compute_element_style(&self, element: &HTMLElement, parent_style: Option<&ComputedStyle>) 
        -> ComputedStyle {
        // Start with default or inherited style
        let mut style = if let Some(parent) = parent_style {
            self.inherit_style(parent)
        } else {
            ComputedStyle::default()
        };
        
        // Apply element-specific defaults
        match element.tag.as_str() {
            "h1" => {
                style.font_size = 32.0;
                style.font_weight = crate::css_parser::FontWeight::Bold;
                style.margin.top = 16.0;
                style.margin.bottom = 16.0;
            }
            "h2" => {
                style.font_size = 24.0;
                style.font_weight = crate::css_parser::FontWeight::Bold;
                style.margin.top = 14.0;
                style.margin.bottom = 14.0;
            }
            "p" => {
                style.margin.top = 8.0;
                style.margin.bottom = 8.0;
            }
            "strong" | "b" => {
                style.font_weight = crate::css_parser::FontWeight::Bold;
            }
            "em" | "i" => {
                style.font_style = crate::css_parser::FontStyle::Italic;
            }
            "code" => {
                style.font_family = vec!["Courier".to_string(), "monospace".to_string()];
            }
            _ => {}
        }
        
        // TODO: Apply CSS rules from stylesheets
        // This would involve selector matching and cascade resolution
        
        style
    }
    
    fn inherit_style(&self, parent: &ComputedStyle) -> ComputedStyle {
        ComputedStyle {
            // Inherit text properties
            font_family: parent.font_family.clone(),
            font_size: parent.font_size,
            font_weight: parent.font_weight,
            font_style: parent.font_style,
            line_height: parent.line_height,
            text_align: parent.text_align,
            color: parent.color,
            
            // Don't inherit box properties
            background_color: None,
            margin: BoxModel { top: 0.0, right: 0.0, bottom: 0.0, left: 0.0 },
            padding: BoxModel { top: 0.0, right: 0.0, bottom: 0.0, left: 0.0 },
            border: crate::css_parser::BorderStyle::default(),
            display: DisplayType::Block,
            position: crate::css_parser::PositionType::Static,
            width: None,
            height: None,
            
            // Inherit NeXT-specific properties
            postscript_font: parent.postscript_font.clone(),
            text_rendering: parent.text_rendering,
        }
    }
}

impl FontMetricsCache {
    fn new() -> Self {
        let mut cache = FontMetricsCache {
            metrics: std::collections::HashMap::new(),
        };
        
        // Pre-populate with common NeXT fonts
        cache.metrics.insert("Times-16".to_string(), FontMetrics {
            ascent: 12.0,
            descent: 4.0,
            line_height: 18.0,
            average_char_width: 8.0,
        });
        
        cache.metrics.insert("Helvetica-16".to_string(), FontMetrics {
            ascent: 12.5,
            descent: 3.5,
            line_height: 18.0,
            average_char_width: 9.0,
        });
        
        cache.metrics.insert("Courier-16".to_string(), FontMetrics {
            ascent: 11.0,
            descent: 4.0,
            line_height: 17.0,
            average_char_width: 10.0, // Fixed width
        });
        
        cache
    }
    
    fn get_or_compute(&mut self, key: &str, style: &ComputedStyle) -> FontMetrics {
        if let Some(metrics) = self.metrics.get(key) {
            return metrics.clone();
        }
        
        // Compute metrics based on font size
        let scale = style.font_size / 16.0;
        
        FontMetrics {
            ascent: 12.0 * scale,
            descent: 4.0 * scale,
            line_height: 18.0 * scale * style.line_height,
            average_char_width: 8.0 * scale,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_simple_layout() {
        let mut engine = LayoutEngine::new(800.0, 600.0);
        
        let element = HTMLElement {
            tag: "div".to_string(),
            attributes: std::collections::HashMap::new(),
            children: vec![
                HTMLNode::Text("Hello, World!".to_string()),
            ],
            computed_style: ComputedStyle::default(),
        };
        
        let layout = engine.compute_layout(&element);
        
        assert!(layout.rect.width > 0.0);
        assert!(layout.rect.height > 0.0);
        assert_eq!(layout.children.len(), 1);
    }
    
    #[test]
    fn test_text_wrapping() {
        let mut engine = LayoutEngine::new(100.0, 600.0);
        let style = ComputedStyle::default();
        
        let text_box = engine.layout_text(
            "This is a long text that should wrap to multiple lines",
            100.0,
            &style
        );
        
        // Should wrap to multiple lines
        if let LayoutContent::Text(text) = &text_box.content {
            assert!(text.contains('\n'));
        }
    }
}