mod demo;

use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use gallery_core::GalleryManifest;
use gallery_media::{CurateOptions, curate_manifest, scan_directory};

#[derive(Parser)]
#[command(
    name = "gallery",
    version,
    about = "Digital Gallery — Turn a folder of photos into a story-driven digital exhibition"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Scan a folder of photos/videos/audio, cluster by EXIF time, and generate a manifest.json draft.
    Scan {
        /// Folder containing your photos, videos, and optional ambient audio.
        input_dir: PathBuf,
        /// Exhibition title.
        #[arg(short, long)]
        title: Option<String>,
        /// Optional exhibition subtitle.
        #[arg(short, long)]
        subtitle: Option<String>,
        /// Optional curator / author name.
        #[arg(short, long)]
        author: Option<String>,
        /// Time gap (in hours) to split into a new exhibition chapter.
        #[arg(long, default_value_t = 4)]
        gap_hours: i64,
        /// Output path for the generated manifest.json (defaults to <input_dir>/manifest.json).
        #[arg(short, long)]
        out: Option<PathBuf>,
    },

    /// Build a standalone HTML exhibition folder (index.html + assets/) or single-file HTML.
    Build {
        /// Path to manifest.json (or a .gallery directory containing manifest.json).
        manifest: PathBuf,
        /// Output directory for the exported exhibition.
        #[arg(short, long, default_value = "./dist")]
        out: PathBuf,
        /// Optional base directory for resolving relative asset paths (defaults to manifest's parent dir).
        #[arg(long)]
        source: Option<PathBuf>,
        /// Export as a single self-contained HTML file (AirDrop / iOS Files / email ready).
        #[arg(long, default_value_t = false)]
        single_file: bool,
    },

    /// Generate a complete sample .gallery package (with artworks & ambient WAV audio) and build it.
    Demo {
        /// Directory where the demo .gallery package and exported HTML will be written.
        #[arg(short, long, default_value = "./demo")]
        out: PathBuf,
    },
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match run(cli) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("error: {err}");
            ExitCode::FAILURE
        }
    }
}

fn run(cli: Cli) -> Result<(), Box<dyn std::error::Error>> {
    match cli.command {
        Commands::Scan {
            input_dir,
            title,
            subtitle,
            author,
            gap_hours,
            out,
        } => {
            let assets = scan_directory(&input_dir)?;
            let derived_title = title.unwrap_or_else(|| {
                input_dir
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("My Exhibition")
                    .replace(['_', '-'], " ")
            });

            let manifest = curate_manifest(
                &assets,
                CurateOptions {
                    title: derived_title,
                    subtitle,
                    author,
                    chapter_gap_hours: gap_hours,
                },
            );

            let out_path = out.unwrap_or_else(|| input_dir.join("manifest.json"));
            manifest.save_to_path(&out_path)?;

            println!("Scanned {} media files.", assets.len());
            println!(
                "Generated {} exhibition scenes -> {}",
                manifest.scenes.len(),
                out_path.display()
            );
            println!(
                "Next: edit {} if desired, then run `gallery build {} --out ./exhibition`",
                out_path.display(),
                out_path.display()
            );
        }

        Commands::Build {
            manifest,
            out,
            source,
            single_file,
        } => {
            let manifest_path = if manifest.is_dir() {
                manifest.join("manifest.json")
            } else {
                manifest
            };
            let source_root = source.unwrap_or_else(|| {
                manifest_path
                    .parent()
                    .map(PathBuf::from)
                    .unwrap_or_else(|| PathBuf::from("."))
            });

            let loaded = GalleryManifest::load_from_path(&manifest_path)?;
            let report = gallery_export::export_exhibition_with_options(
                &loaded,
                &source_root,
                &out,
                gallery_export::ExportOptions {
                    single_file_html: single_file,
                    ..Default::default()
                },
            )?;

            println!("Built exhibition: {}", report.output_html.display());
            println!(
                "Copied {} asset(s) ({} image(s) optimized).",
                report.copied_assets.len(),
                report.optimized_images
            );
            if !report.missing_assets.is_empty() {
                eprintln!(
                    "Warning: {} referenced asset(s) were not found under {}:",
                    report.missing_assets.len(),
                    source_root.display()
                );
                for missing in &report.missing_assets {
                    eprintln!("  - {missing}");
                }
            }
        }

        Commands::Demo { out } => {
            demo::generate_demo(&out)?;
        }
    }

    Ok(())
}
