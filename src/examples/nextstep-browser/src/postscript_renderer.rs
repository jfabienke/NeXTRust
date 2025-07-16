// PostScript Renderer for NeXTSTEP Browser
// Renders HTML/CSS to Display PostScript using NeXT's advanced graphics

use std::collections::HashMap;
use crate::layout::{LayoutBox, LayoutContent};
use crate::css_parser::{Color, ComputedStyle, DisplayType, TextAlign};

#[derive(Debug, Clone)]
pub struct PostScriptRenderer {
    current_context: PSContext,
    font_cache: HashMap<String, FontMetrics>,
    current_y: f32,
}

#[derive(Debug, Clone)]
pub struct PSContext {
    pub width: f32,
    pub height: f32,
    pub scale: f32,
    pub origin_x: f32,
    pub origin_y: f32,
}

#[derive(Debug, Clone)]
pub struct FontMetrics {
    pub ascent: f32,
    pub descent: f32,
    pub line_height: f32,
    pub space_width: f32,
}

pub struct PSNode {
    pub id: String,
    pub content: PSContent,
    pub transform: Transform,
}

pub enum PSContent {
    Group { children: Vec<PSNode> },
    Rectangle { x: f32, y: f32, width: f32, height: f32, fill: Option<Color>, stroke: Option<Color> },
    Text { x: f32, y: f32, text: String, font: String, size: f32, color: Color },
    Path { commands: Vec<PathCommand> },
    Image { x: f32, y: f32, width: f32, height: f32, data: Vec<u8> },
}

#[derive(Debug, Clone, Default)]
pub struct Transform {
    pub translate_x: f32,
    pub translate_y: f32,
    pub scale_x: f32,
    pub scale_y: f32,
    pub rotate: f32,
}

#[derive(Debug, Clone)]
pub enum PathCommand {
    MoveTo(f32, f32),
    LineTo(f32, f32),
    CurveTo(f32, f32, f32, f32, f32, f32),
    ClosePath,
}

impl PostScriptRenderer {
    pub fn new() -> Self {
        PostScriptRenderer {
            current_context: PSContext {
                width: 800.0,
                height: 600.0,
                scale: 1.0,
                origin_x: 0.0,
                origin_y: 0.0,
            },
            font_cache: Self::initialize_font_cache(),
            current_y: 0.0,
        }
    }
    
    fn initialize_font_cache() -> HashMap<String, FontMetrics> {
        let mut cache = HashMap::new();
        
        // NeXT's default fonts with metrics
        cache.insert("Times".to_string(), FontMetrics {
            ascent: 11.0,
            descent: 3.0,
            line_height: 14.0,
            space_width: 3.5,
        });
        
        cache.insert("Helvetica".to_string(), FontMetrics {
            ascent: 11.5,
            descent: 2.5,
            line_height: 14.0,
            space_width: 4.0,
        });
        
        cache.insert("Courier".to_string(), FontMetrics {
            ascent: 10.0,
            descent: 3.0,
            line_height: 13.0,
            space_width: 6.0,
        });
        
        cache
    }
    
    pub fn render(&mut self, layout_tree: &LayoutBox) -> String {
        let mut ps_code = String::new();
        
        // PostScript header
        ps_code.push_str("%!PS-Adobe-3.0\n");
        ps_code.push_str("%%Creator: NeXTSTEP Web Browser\n");
        ps_code.push_str("%%BoundingBox: 0 0 ");
        ps_code.push_str(&format!("{} {}\n", self.current_context.width, self.current_context.height));
        ps_code.push_str("%%EndComments\n\n");
        
        // Setup coordinate system (flip Y for PostScript)
        ps_code.push_str(&format!("0 {} translate\n", self.current_context.height));
        ps_code.push_str("1 -1 scale\n\n");
        
        // Reset current Y position
        self.current_y = 0.0;
        
        // Render the layout tree
        ps_code.push_str(&self.render_layout_box(layout_tree));
        
        // PostScript trailer
        ps_code.push_str("\nshowpage\n");
        ps_code.push_str("%%EOF\n");
        
        ps_code
    }
    
    fn render_layout_box(&mut self, layout_box: &LayoutBox) -> String {
        let mut ps = String::new();
        
        // Save graphics state
        ps.push_str("gsave\n");
        
        // Render background if present
        if let Some(bg_color) = &layout_box.style.background_color {
            ps.push_str(&self.render_rectangle(
                layout_box.rect.x,
                layout_box.rect.y,
                layout_box.rect.width,
                layout_box.rect.height,
                Some(*bg_color),
                None
            ));
        }
        
        // Render border if present
        if layout_box.style.border.width > 0.0 {
            ps.push_str(&self.render_rectangle(
                layout_box.rect.x,
                layout_box.rect.y,
                layout_box.rect.width,
                layout_box.rect.height,
                None,
                Some(layout_box.style.border.color)
            ));
        }
        
        // Render content
        match &layout_box.content {
            LayoutContent::Text(text) => {
                ps.push_str(&self.render_text(
                    layout_box.rect.x + layout_box.style.padding.left,
                    layout_box.rect.y + layout_box.style.padding.top,
                    text,
                    &layout_box.style
                ));
            }
            LayoutContent::Element(_) => {
                // Render children
                for child in &layout_box.children {
                    ps.push_str(&self.render_layout_box(child));
                }
            }
        }
        
        // Restore graphics state
        ps.push_str("grestore\n");
        
        ps
    }
    
    fn render_rectangle(&self, x: f32, y: f32, width: f32, height: f32, 
                       fill: Option<Color>, stroke: Option<Color>) -> String {
        let mut ps = String::new();
        
        // Define rectangle path
        ps.push_str(&format!("{} {} moveto\n", x, y));
        ps.push_str(&format!("{} {} lineto\n", x + width, y));
        ps.push_str(&format!("{} {} lineto\n", x + width, y + height));
        ps.push_str(&format!("{} {} lineto\n", x, y + height));
        ps.push_str("closepath\n");
        
        // Fill if color provided
        if let Some(color) = fill {
            ps.push_str(&format!("{} {} {} setrgbcolor\n", color.r, color.g, color.b));
            ps.push_str("fill\n");
        }
        
        // Stroke if color provided
        if let Some(color) = stroke {
            ps.push_str(&format!("{} {} {} setrgbcolor\n", color.r, color.g, color.b));
            ps.push_str("stroke\n");
        }
        
        ps
    }
    
    fn render_text(&mut self, x: f32, y: f32, text: &str, style: &ComputedStyle) -> String {
        let mut ps = String::new();
        
        // Get font name (map to PostScript font)
        let font_name = self.map_font_name(&style.font_family[0]);
        
        // Set font
        ps.push_str(&format!("/{} findfont {} scalefont setfont\n", 
                            font_name, style.font_size));
        
        // Set text color
        ps.push_str(&format!("{} {} {} setrgbcolor\n", 
                            style.color.r, style.color.g, style.color.b));
        
        // Get font metrics
        let metrics = self.font_cache.get(&font_name)
            .cloned()
            .unwrap_or(FontMetrics {
                ascent: style.font_size * 0.8,
                descent: style.font_size * 0.2,
                line_height: style.font_size * 1.2,
                space_width: style.font_size * 0.3,
            });
        
        // Position text (account for baseline)
        let baseline_y = y + metrics.ascent;
        
        // Handle text alignment
        let text_x = match style.text_align {
            TextAlign::Left => x,
            TextAlign::Center => x + (style.width.as_ref().map(|w| match w {
                crate::css_parser::Length::Px(px) => px / 2.0,
                _ => 0.0,
            }).unwrap_or(0.0)),
            TextAlign::Right => x + (style.width.as_ref().map(|w| match w {
                crate::css_parser::Length::Px(px) => *px,
                _ => 0.0,
            }).unwrap_or(0.0)),
            TextAlign::Justify => x, // TODO: Implement justification
        };
        
        // Move to text position
        ps.push_str(&format!("{} {} moveto\n", text_x, baseline_y));
        
        // Show text (escape special PostScript characters)
        let escaped_text = self.escape_postscript_string(text);
        ps.push_str(&format!("({}) show\n", escaped_text));
        
        // Update current Y position
        self.current_y = y + metrics.line_height;
        
        ps
    }
    
    fn map_font_name(&self, font_family: &str) -> String {
        match font_family.to_lowercase().as_str() {
            "serif" | "times" | "times new roman" => "Times-Roman",
            "sans-serif" | "helvetica" | "arial" => "Helvetica",
            "monospace" | "courier" | "monaco" => "Courier",
            "helvetica bold" | "helvetica-bold" => "Helvetica-Bold",
            "times bold" | "times-bold" => "Times-Bold",
            "times italic" | "times-italic" => "Times-Italic",
            _ => "Helvetica", // Default fallback
        }.to_string()
    }
    
    fn escape_postscript_string(&self, text: &str) -> String {
        text.chars()
            .map(|c| match c {
                '(' => "\\(".to_string(),
                ')' => "\\)".to_string(),
                '\\' => "\\\\".to_string(),
                '\n' => "\\n".to_string(),
                '\r' => "\\r".to_string(),
                '\t' => "\\t".to_string(),
                _ => c.to_string(),
            })
            .collect()
    }
    
    pub fn render_image(&self, x: f32, y: f32, width: f32, height: f32, 
                       image_data: &[u8], format: ImageFormat) -> String {
        let mut ps = String::new();
        
        ps.push_str("gsave\n");
        ps.push_str(&format!("{} {} translate\n", x, y));
        ps.push_str(&format!("{} {} scale\n", width, height));
        
        match format {
            ImageFormat::JPEG => {
                // Use NeXT's built-in JPEG support
                ps.push_str("/DeviceRGB setcolorspace\n");
                ps.push_str(&format!("<<\n"));
                ps.push_str(&format!("  /ImageType 1\n"));
                ps.push_str(&format!("  /Width {}\n", width as i32));
                ps.push_str(&format!("  /Height {}\n", height as i32));
                ps.push_str(&format!("  /BitsPerComponent 8\n"));
                ps.push_str(&format!("  /Decode [0 1 0 1 0 1]\n"));
                ps.push_str(&format!("  /ImageMatrix [{} 0 0 {} 0 0]\n", width, -height));
                ps.push_str(&format!("  /DataSource currentfile /DCTDecode filter\n"));
                ps.push_str(&format!(">> image\n"));
                
                // Embed JPEG data
                ps.push_str(&base64::encode(image_data));
                ps.push_str("\n");
            }
            ImageFormat::GIF | ImageFormat::PNG => {
                // Convert to raw RGB for PostScript
                // This would involve decoding the image format
                ps.push_str("% Image placeholder\n");
                ps.push_str(&self.render_rectangle(0.0, 0.0, 1.0, 1.0, 
                    Some(Color { r: 0.9, g: 0.9, b: 0.9, a: 1.0 }), 
                    Some(Color::BLACK)));
            }
        }
        
        ps.push_str("grestore\n");
        ps
    }
}

#[derive(Debug, Clone, Copy)]
pub enum ImageFormat {
    JPEG,
    GIF,
    PNG,
}

// Base64 encoding for embedded images
mod base64 {
    pub fn encode(data: &[u8]) -> String {
        // Simplified base64 encoding
        const CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut result = String::new();
        
        for chunk in data.chunks(3) {
            let mut buf = [0u8; 3];
            for (i, &byte) in chunk.iter().enumerate() {
                buf[i] = byte;
            }
            
            let b = ((buf[0] as u32) << 16) | ((buf[1] as u32) << 8) | (buf[2] as u32);
            
            result.push(CHARS[((b >> 18) & 0x3F) as usize] as char);
            result.push(CHARS[((b >> 12) & 0x3F) as usize] as char);
            
            if chunk.len() > 1 {
                result.push(CHARS[((b >> 6) & 0x3F) as usize] as char);
            } else {
                result.push('=');
            }
            
            if chunk.len() > 2 {
                result.push(CHARS[(b & 0x3F) as usize] as char);
            } else {
                result.push('=');
            }
        }
        
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_postscript_escaping() {
        let renderer = PostScriptRenderer::new();
        assert_eq!(renderer.escape_postscript_string("Hello (World)"), 
                   "Hello \\(World\\)");
        assert_eq!(renderer.escape_postscript_string("Back\\slash"), 
                   "Back\\\\slash");
    }
    
    #[test]
    fn test_font_mapping() {
        let renderer = PostScriptRenderer::new();
        assert_eq!(renderer.map_font_name("Arial"), "Helvetica");
        assert_eq!(renderer.map_font_name("Times New Roman"), "Times-Roman");
        assert_eq!(renderer.map_font_name("Courier"), "Courier");
    }
}