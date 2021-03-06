#' Animate a ppn game
#'
#' Animate a ppn game
#' @param game A list containing a parsed ppn game (as parsed by \code{read_ppn})
#' @param file Filename to save animation unless \code{NULL}
#'             in which case it uses the current graphics device.
#' @param annotate If `TRUE` or `"algebraic"` annotate the plot
#'                  with \dQuote{algrebraic} coordinates,
#'                 if `FALSE` or `"none"` don't annotate,
#'                 if `"cartesian"` annotate the plot with \dQuote{cartesian} coordinates.
#' @param ... Arguments to \code{pmap_piece}
#' @param .f Low level graphics function to use e.g. \code{grid.piece}, \code{piece3d}, or \code{piece}.
#' @param cfg A piecepackr configuration list
#' @param envir Environment (or named list) of piecepackr configuration lists
#' @param n_transitions Integer, if over zero (the default)
#'                how many transition frames to add between moves.
#' @param n_pauses Integer, how many paused frames per completed move.
#' @param fps Double, frames per second.
#' @param width Width of animation (in inches).  Inferred by default.
#' @param height Height of animation (in inches).  Inferred by default.
#' @param ppi Resolution of animation in pixels per inch.
#'            By default set so image max 600 pixels wide or tall.
#' @param new_device If \code{file} is \code{NULL} should we open up a new graphics device?
#' @inheritParams cat_piece
#' @return Nothing, as a side effect saves an animation of ppn game
#' @export
animate_game <- function(game, file = "animation.gif", annotate = TRUE, ...,
                         .f = piecepackr::grid.piece, cfg = NULL, envir = NULL,
                         n_transitions = 0L, n_pauses = 1L, fps = n_transitions + n_pauses,
                         width = NULL, height = NULL, ppi = NULL,
                         new_device = TRUE, annotation_scale = NULL) {

    if (n_transitions > 0L) piecepackr:::assert_suggested("tweenr")

    ce <- piecepackr:::default_cfg_envir(cfg, envir)
    cfg <- ce$cfg
    envir <- ce$envir

    dfs <- game$dfs
    ranges <- lapply(dfs, aabb_piece, cfg = cfg, envir = envir, ...)
    if (n_transitions > 0L) {
        dfs <- get_tweened_dfs(dfs, n_transitions, ..., cfg = cfg, envir = envir)
    }

    #### Add grid and comment annotations
    xmax_op <- max(sapply(ranges, function(r) r$x_op[2]), na.rm = TRUE)
    ymax_op <- max(sapply(ranges, function(r) r$y_op[2]), na.rm = TRUE)
    xmin_op <- min(sapply(ranges, function(r) r$x_op[1]), na.rm = TRUE)
    ymin_op <- min(sapply(ranges, function(r) r$y_op[1]), na.rm = TRUE)
    xmax <- max(sapply(ranges, function(r) r$x[2]), na.rm = TRUE)
    ymax <- max(sapply(ranges, function(r) r$y[2]), na.rm = TRUE)
    xoffset <- min2offset(xmin_op)
    yoffset <- min2offset(ymin_op)
    if (is.null(width)) width <- xmax_op + xoffset + 0.50
    if (is.null(height)) height <- ymax_op + yoffset + 0.50
    m <- max(width, height)
    if (is.null(ppi)) ppi <- round(600 / m, 0)
    # mp4 needs even height / weight
    height <- ceiling(ppi * height)
    width <- ceiling(ppi * width)
    height <- height + (height %% 2)
    width <- width + (width %% 2)
    plot_fn <- plot_fn_helper(.f, xmax, ymax, xoffset, yoffset, width, height, m, ppi, envir,
                              annotate, annotation_scale)
    animation_fn(file, new_device)(lapply(dfs, plot_fn, ...), file, width, height, 1 / fps, ppi)
    invisible(NULL)
}
#### How to handle empty tibbles??
animation_fn <- function(file, new_device = TRUE) {
    if (is.null(file)) {
        function(expr, file, width, height, delay, res) {
            if (new_device) dev.new(width = width / res, height = height / res, unit = "in", noRstudioGD = TRUE)
            devAskNewPage(TRUE)
            eval(expr)
            devAskNewPage(getOption("device.ask.default"))
        }
    } else if (grepl(".html$", file)) {
        piecepackr:::assert_suggested("animation")
        function(expr, file, width, height, delay, res) {
            animation::saveHTML(expr, htmlfile = file, interval = delay, img.name = file,
                                ani.height = height, ani.width = width, ani.res = res,
                                ani.dev = "png", ani.type = "png",
                                title = "Animated game", verbose = FALSE)
        }
    } else if (grepl(".gif$", file)) {
        if (requireNamespace("gifski", quietly = TRUE)) {
            function(expr, file, width, height, delay, res) {
                gifski::save_gif(expr, file, width, height, delay, res = res, progress = FALSE)
            }
        } else if (requireNamespace("animation", quietly = TRUE)) {
            function(expr, file, width, height, delay, res) {
                animation::saveGIF(expr, movie.name = file, interval = delay, img.name = file,
                                   ani.height = height, ani.width = width, ani.res = res,
                                   ani.dev = "png", ani.type = "png")
            }
        } else {
            abort(c("At least one the suggested packages 'gifski' or 'animation' is required to use 'animate_game()'.",
                    i = "Use 'install.packages(\"gifski\")' and/or 'install.packages(\"animation\")' to install them."),
                  class = "suggested_package")
        }
    } else {
        piecepackr:::assert_suggested("animation")
        function(expr, file, width, height, delay, res) {
            animation::saveVideo(expr, video.name = file, interval = delay, img.name = file,
                                ani.height = height, ani.width = width, ani.res = res,
                                ani.dev = "png", ani.type = "png",
                                title = "Animated game", verbose = FALSE)
        }
    }
}

#' @importFrom dplyr bind_rows left_join matches select
get_tweened_dfs <- function(dfs, n_transitions = 0L, n_pauses = 1L, ...) {
    n <- length(dfs)
    if (n < 2) return(rep(dfs, n_pauses))
    new_dfs <- list()
    for (i in seq_len(n - 1)) {
        new_dfs <- append(new_dfs, rep(dfs[i], n_pauses))
        new_dfs <- append(new_dfs, tween_dfs(dfs[[i]], dfs[[i+1]], n_transitions))
    }
    new_dfs <- append(new_dfs, rep(dfs[n], n_pauses))
    for (i in seq_along(new_dfs))
        attr(new_dfs[[i]], "scale_factor") <- attr(dfs[[1]], "scale_factor")
    new_dfs
}

#' @importFrom utils hasName packageVersion
tween_dfs <- function(df1, df2, n_transitions = 0L) {
    df_id_cfg <- get_id_cfg(df1, df2)
    if (nrow(df1) == 0 && nrow(df2) == 0) return(rep(list(df1), n_transitions))
    dfs <- init_dfs(df1, df2)
    df <- tweenr::tween_state(dfs[[1]], dfs[[2]], ease = "cubic-in-out",
                              nframes = n_transitions + 2L, id = .data$id)
    df <- left_join(df, df_id_cfg, by = "id")
    id_frames <- as.list(seq.int(max(df$.frame)))
    l <- lapply(id_frames, function(id_frame) dplyr::filter(df, .data$.frame == id_frame))
    l <- utils::head(l, -1L)
    l <- utils::tail(l, -1L)
    l
}
init_dfs <- function(df1, df2) {
    if (nrow(df1) == 0) {
        df1i <- get_tweenr_df(df2)
        df1i$scale <- 0
    } else {
        df1i <- get_tweenr_df(df1)
    }
    if (nrow(df2) == 0) {
        df2i <- get_tweenr_df(df1)
        df2i$scale <- 0
    } else {
        df2i <- get_tweenr_df(df2)
    }
    df2_anti <- filter(df2i, match(.data$id, df1i$id, 0) == 0)
    df2_anti$scale <- rep(0, nrow(df2_anti))
    df1 <- bind_rows(df1i, df2_anti) # 'added' pieces
    df1_anti <- filter(df1i, match(.data$id, df2i$id, 0) == 0)
    df1_anti$scale <- rep(0, nrow(df1_anti))
    df2 <- df2i # 'removed' pieces
    while (nrow(df1_anti)) {
        row <- df1_anti[1L, ]
        df1_anti <- df1_anti[-1L, ]
        prev_index <- find_good_prev_index(row, df1i, df2i)
        df2 <- insert_df(df2, row, prev_index)
    }
    df1 <- df1[match(df2$id, df1$id), ] # re-sort to match df2
    list(df1, df2)
}
find_good_prev_index <- function(row, df1i, df2i) {
    prev_index <- Inf
    index <- which(df1i$id == row$id)
    while (is.infinite(prev_index)) {
        index <- index - 1
        if (index == 0) {
            prev_index <- 0
        } else {
            prev <- df1i[index, ]
            index2 <- which(df2i$id == prev$id)
            if (length(index2)) {
                prev2 <- df2i[index2, ]
                if (near(prev$x, prev2$x) && near(prev$y, prev2$y)) {
                    prev_index <- index2
                }
            }
        }
    }
    prev_index
}
get_id_cfg <- function(df1, df2) {
    df <- bind_rows(df1, df2)
    df <- select(df, .data$id, .data$cfg)
    unique(df)
}
get_tweenr_df <- function(df, ...) {
    df$scale <- 1
    df$alpha <- 1
    df <- select(df, .data$id, .data$piece_side, .data$suit, .data$rank,
                 .data$x, .data$y, matches("^z$"), .data$angle,
                 .data$scale, .data$alpha)
    as.data.frame(df)
}

get_df_from_move <- function(game, move = NULL) {
    if (is.null(move)) {
        utils::tail(game$dfs, 1)[[1]]
    } else {
        game$dfs[[move]]
    }
}

plot_fn_helper <- function(.f = grid.piece, xmax, ymax, xoffset, yoffset,
                           width, height, m, ppi, envir, annotate, annotation_scale) {
    if (identical(.f, grid.piece)) {
        function(df, ..., scale = 1) {
            annotation_scale <- annotation_scale %||% attr(df, "scale_factor") %||% 1
            df$x <- df$x + xoffset
            df$y <- df$y + yoffset
            df$scale <- if (hasName(df, "scale")) scale * df$scale else scale
            grid::grid.newpage()
            pmap_piece(df, default.units = "in", ..., envir = envir)
            annotate_plot(annotate, xmax, ymax, xoffset, yoffset, annotation_scale)
        }
    } else if (identical(.f, piece3d)) {
        piecepackr:::assert_suggested("rgl")
        if (Sys.which("wmctrl") != "") system(paste0("wmctrl -r RGL -e 0,-1,-1,", width, ",", height))
        f <- tempfile(fileext=".png")
        function(df, ..., scale = 1) {
            df$scale <- if (hasName(df, "scale")) scale * df$scale else scale
            rgl::rgl.clear()
            rgl::points3d(x = rep(c(0, xmax), 2), y = rep(c(0, ymax), each = 2), z = 0, alpha = 0)
            pmap_piece(df, piece3d, ..., envir = envir)
            Sys.sleep(2)
            rgl::rgl.snapshot(f, top = FALSE)
            grid::grid.newpage()
            grid::grid.raster(png::readPNG(f))
        }
    } else if (identical(.f, piece)) {
        piecepackr:::assert_suggested("rayrender")
        function(df, ..., scale = 1,
                 fov = 20, samples=100, lookat = NULL, lookfrom = NULL, clamp_value = Inf,
                 table = NA) {
            df$scale <- if (hasName(df, "scale")) scale * df$scale else scale
            df$x <- df$x + xoffset
            df$y <- df$y + yoffset
            l <- pmap_piece(df, piece, ..., envir = envir)
            if (all(is.na(table))) {
                table <- rayrender::sphere(z=-1e3, radius=1e3, material=rayrender::diffuse(color="green"))
                light <- rayrender::sphere(x=0.5*width/ppi, y=-4, z=max(1.5*m+1, 20),
                                           material=rayrender::light(intensity=420))
                table <- rayrender::add_object(table, light)
            }
            scene <- Reduce(rayrender::add_object, l, init=table)
            if (is.null(lookat)) lookat <- c(0.5*width/ppi, 0.5*height/ppi, 0)
            if (is.null(lookfrom)) lookfrom <- c(0.5*width/ppi, -7, 1.5*m)
            rayrender::render_scene(scene,
                                    fov = fov, samples = samples,
                                    lookat = lookat, lookfrom = lookfrom, clamp_value = clamp_value,
                                    width = width, height = height)
        }
    } else {
        .f
    }
}

min2offset <- function(min, lbound = 0.5) {
    if (is.na(min)) {
        NA_real_
    } else if (min < lbound) {
        lbound - min
    } else {
        0
    }
}

annotate_plot <- function(annotate, xmax, ymax, xoffset = 0, yoffset = 0, annotation_scale = 1) {
        if (isFALSE(annotate) || annotate == "none" || is.na(xmax) || is.na(ymax))
            return(invisible(NULL))
        gp <- gpar(fontsize = 18, fontface = "bold")
        x_coords <- seq(annotation_scale, floor(xmax), by = annotation_scale)
        if (annotate == "cartesian")
            l <- as.character(seq_along(x_coords))
        else
            l <- letters[seq_along(x_coords)]
        l <- stringr::str_pad(l, max(stringr::str_count(l)))
        grid.text(l, x = x_coords + xoffset, y = 0.25, default.units = "in", gp = gp)
        y_coords <- seq(annotation_scale, floor(ymax), by = annotation_scale)
        n <- as.character(seq_along(y_coords))
        n <- stringr::str_pad(n, max(stringr::str_count(n)))
        grid.text(n, x = 0.25, y = y_coords + yoffset, default.units = "in", gp = gp)
        invisible(NULL)
}
