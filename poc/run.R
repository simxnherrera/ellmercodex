source_file <- tryCatch(sys.frame(1)$ofile, error = function(error) NULL)
if (is.null(source_file)) source_file <- file.path(getwd(), "poc", "run.R")
poc_dir <- dirname(normalizePath(source_file, mustWork = TRUE))

for (file in c("config.R", "credentials.R", "auth.R", "transport.R", "ellmer.R")) {
  source(file.path(poc_dir, file), local = globalenv())
}

rm(source_file, poc_dir, file)
