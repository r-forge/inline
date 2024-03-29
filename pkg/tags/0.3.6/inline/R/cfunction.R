# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
## CFunc is an S4 class derived from 'function'. This inheritance allows objects
## to behave exactly as functions do, but it provides a slot @code that keeps the
## source C or Fortran code used to create the inline call
setClass("CFunc",
  representation(
    code="character"
  ),
  contains="function"
)

setClass( "CFuncList", contains = "list" )

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
cfunction <- function(sig=character(), body=character(), includes=character(), otherdefs=character(),
                      language=c("C++", "C", "Fortran", "F95", "ObjectiveC", "ObjectiveC++"),
                      verbose=FALSE, convention=c(".Call", ".C", ".Fortran"), Rcpp=FALSE,
                      cppargs=character(), cxxargs=character(), libargs=character()) {

  convention <- match.arg(convention)

  if ( missing(language) ) language <- ifelse(convention == ".Fortran", "Fortran", "C++")
  else language <- match.arg(language)

  language <- switch(EXPR=tolower(language), cpp="C++", f="Fortran", f95="F95",
                     objc="ObjectiveC", objcpp= ,"objc++"="ObjectiveC++", language)

  f <- basename(tempfile())

  if ( !is.list(sig) ) {
    sig <- list(sig)
    names(sig) <- f
    names(body) <- f
  }
  if( length(sig) != length(body) )
    stop("mismatch between the number of functions declared in 'sig' and the number of function bodies provided in 'body'")

  if (Rcpp) {
      if (!require(Rcpp)) stop("Rcpp cannot be loaded, install it or use the default Rcpp=FALSE")
      cxxargs <- c(Rcpp:::RcppCxxFlags(), cxxargs)	# prepend information from Rcpp
      libargs <- c(Rcpp:::RcppLdFlags(), libargs)	# prepend information from Rcpp
  }
  if (length(cppargs) != 0) {
      args <- paste(cppargs, collapse=" ")
      if (verbose) cat("Setting PKG_CPPFLAGS to", args, "\n")
      Sys.setenv(PKG_CPPFLAGS=args)
  }
  if (length(cxxargs) != 0) {
      args <- paste(cxxargs, collapse=" ")
      if (verbose) cat("Setting PKG_CXXFLAGS to", args, "\n")
      Sys.setenv(PKG_CXXFLAGS=args)
  }
  if (length(libargs) != 0) {
      args <- paste(libargs, collapse=" ")
      if (verbose) cat("Setting PKG_LIBS to", args, "\n")
      Sys.setenv(PKG_LIBS=args)
  }

  ## GENERATE THE CODE
  for ( i in seq_along(sig) ) {
    ## C/C++ with .Call convention *********************************************
    if ( convention == ".Call" ) {
  	  ## include R includes, also error
  	  if (i == 1) {
	      code <- ifelse(Rcpp,
                         "#include <Rcpp.h>\n",
                         paste("#include <R.h>\n#include <Rdefines.h>\n",
                               "#include <R_ext/Error.h>\n", sep=""));
	      ## include further includes
	      code <- paste(c(code, includes, ""), collapse="\n")
	      ## include further definitions
	      code <- paste(c(code, otherdefs, ""), collapse="\n")
      }
  	  ## generate C-function sig from the original sig
  	  if ( length(sig[[i]]) > 0 ) {
  	    funCsig <- paste("SEXP", names(sig[[i]]), collapse=", " )
  	  }
  	  else funCsig <- ""
  	  funCsig <- paste("SEXP", names(sig)[i], "(", funCsig, ")", sep=" ")
  	  ## add C export of the function
  	  if ( language == "C++" || language == "ObjectiveC++")
  	    code <- paste( code, "extern \"C\" {\n  ", funCsig, ";\n}\n\n", sep="")
  	  ## OPEN function
  	  code <- paste( code, funCsig, " {\n", sep="")
  	  ## add code, split lines
  	  code <- paste( code, paste(body[[i]], collapse="\n"), sep="")
  	  ## CLOSE function, add return and warning in case the user forgot it
  	  code <- paste(code, "\n  ",
                    ifelse(Rcpp, "Rf_warning", "warning"),
                    "(\"your C program does not return anything!\");\n  return R_NilValue;\n}\n", sep="");
    }

    ## C/C++ with .C convention ************************************************
    else if ( convention == ".C" ) {
  	  if (i == 1) {
	      ## include only basic R includes
	      code <- ifelse(Rcpp,"#include <Rcpp.h>\n", "#include <R.h>\n")
	      ## include further includes
	      code <- paste(c(code, includes, ""), collapse="\n")
	      ## include further definitions
	      code <- paste(c(code, otherdefs, ""), collapse="\n")
      }
  	  ## determine function header
  	  if ( length(sig[[i]]) > 0 ) {
  	    types <- pmatch(sig[[i]], c("logical", "integer", "double", "complex",
  	                       "character", "raw", "numeric"), duplicates.ok = TRUE)
  	    if ( any(is.na(types)) ) stop( paste("Unrecognized type", sig[[i]][is.na(types)]) )
  	    decls <- c("int *", "int *", "double *", "Rcomplex *", "char **",
  	               "unsigned char *", "double *")[types]
  	    funCsig <- paste(decls, names(sig[[i]]), collapse=", ")
	    }
	    else funCsig <- ""
  	  funCsig <- paste("void", names(sig)[i], "(", funCsig, ")", sep=" ")
	    if ( language == "C++" || language == "ObjectiveC++" )
	      code <- paste( code, "extern \"C\" {\n  ", funCsig, ";\n}\n\n", sep="")
  	  ## OPEN function
  	  code <- paste( code, funCsig, " {\n", sep="")
  	  ## add code, split lines
  	  code <- paste( code, paste(body[[i]], collapse="\n"), sep="")
  	  ## CLOSE function
  	  code <- paste( code, "\n}\n", sep="")
    }
    ## .Fortran convention *****************************************************
    else {
  	  if (i == 1) {
	      ## no default includes, include further includes
	      code <- paste(includes, collapse="\n")
	      ## include further definitions
	      code <- paste(c(code, otherdefs, ""), collapse="\n")
      }
  	  ## determine function header
  	  if ( length(sig[[i]]) > 0 ) {
  	    types <- pmatch(sig[[i]], c("logical", "integer", "double", "complex",
  	                       "character", "raw", "numeric"), duplicates.ok = TRUE)
  	    if ( any(is.na(types)) ) stop( paste("Unrecognized type", sig[[i]][is.na(types)]) )
  	    if (6 %in% types) stop( "raw type unsupported by .Fortran()" )
  	    decls <- c("INTEGER", "INTEGER", "DOUBLE PRECISION", "DOUBLE COMPLEX",
  	               "CHARACTER*255", "Unsupported", "DOUBLE PRECISION")[types]
  	    decls <- paste("      ", decls, " ", names(sig[[i]]), "(*)", sep="", collapse="\n")
  	    funCsig <- paste(names(sig[[i]]), collapse=", ")
  	  }
  	  else {
	      decls <- ""
	      funCsig <- ""
	    }
  	  funCsig <- paste("      SUBROUTINE", names(sig)[i], "(", funCsig, ")\n", sep=" ")
  	  ## OPEN function
  	  code <- paste( code, funCsig, decls, collapse="\n")
  	  ## add code, split lines
  	  code <- paste( code, paste(body[[i]], collapse="\n"), sep="")
  	  ## CLOSE function
  	  code <- paste( code, "\n      RETURN\n      END\n", sep="")
    }
  } ## for along signatures

  ## WRITE AND COMPILE THE CODE
  libLFile <- compileCode(f, code, language, verbose)

  ## SET A FINALIZER TO PERFORM CLEANUP
  cleanup <- function(env) {
    if ( f %in% names(getLoadedDLLs()) ) dyn.unload(libLFile)
    unlink(libLFile)
  }
  reg.finalizer(environment(), cleanup, onexit=TRUE)

  res <- vector("list", length(sig))
  names(res) <- names(sig)

  ## GENERATE R FUNCTIONS
  for ( i in seq_along(sig) ) {
    ## Create new objects of class CFunc, each containing the code of ALL inline
    ## functions. This will be used to recompile the whole shared lib when needed
    res[[i]] <- new("CFunc", code = code)

    ## this is the skeleton of the function, the external call is added below using 'body'
    ## important here: all variables are kept in the local environment
    fn <- function(arg) {
   	  if ( !file.exists(libLFile) )
   	    libLFile <<- compileCode(f, code, language, verbose)
   	  if ( !( f %in% names(getLoadedDLLs()) ) ) dyn.load(libLFile)
    }

    ## Modify the function formals to give the right argument list
    args <- formals(fn)[ rep(1, length(sig[[i]])) ]
    names(args) <- names(sig[[i]])
    formals(fn) <- args

    ## create .C/.Call function call that will be added to 'fn'
    if (convention == ".Call") {
      body <- quote( CONVENTION("EXTERNALNAME", PACKAGE=f, ARG) )[ c(1:3, rep(4, length(sig[[i]]))) ]
      for ( j in seq(along = sig[[i]]) ) body[[j+3]] <- as.name(names(sig[[i]])[j])
    }
    else {
      body <- quote( CONVENTION("EXTERNALNAME", PACKAGE=f, as.logical(ARG), as.integer(ARG),
                    as.double(ARG), as.complex(ARG), as.character(ARG),
          			    as.character(ARG), as.double(ARG)) )[ c(1:3,types+3) ]
      names(body) <- c( NA, "name", "PACKAGE", names(sig[[i]]) )
      for ( j in seq(along = sig[[i]]) ) body[[j+3]][[2]] <- as.name(names(sig[[i]])[j])
    }
    body[[1]] <- as.name(convention)
    body[[2]] <- names(sig)[i]
    ## update the body of 'fn'
    body(fn)[[4]] <- body
    ## set fn as THE function in CFunc of res[[i]]
    res[[i]]@.Data <- fn
  }

  ## OUTPUT PROGRAM CODE IF DESIRED
  if ( verbose ) {
    cat("Program source:\n")
    lines <- strsplit(code, "\n")
    for ( i in 1:length(lines[[1]]) )
      cat(format(i,width=3), ": ", lines[[1]][i], "\n", sep="")
  }

  ## Remove unnecessary objects from the local environment
  remove(list = c("args", "body", "convention", "fn", "funCsig", "i", "includes", "j"))

  ## RETURN THE FUNCTION
  if (length(res) == 1 && names(res) == f) return( res[[1]] )
  else return( new( "CFuncList", res ) )
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
compileCode <- function(f, code, language, verbose) {
  wd = getwd()
  on.exit(setwd(wd))
  ## Prepare temp file names
  if ( .Platform$OS.type == "windows" ) {
    ## windows files
    dir <- gsub("\\\\", "/", tempdir())
    libCFile  <- paste(dir, "/", f, ".EXT", sep="")
    libLFile  <- paste(dir, "/", f, ".dll", sep="")
    libLFile2 <- paste(dir, "/", f, ".dll", sep="")
  }
  else {
    ## UNIX-alike build
    libCFile  <- paste(tempdir(), "/", f, ".EXT", sep="")
    libLFile  <- paste(tempdir(), "/", f, ".so", sep="")
    libLFile2 <- paste(tempdir(), "/", f, ".sl", sep="")
  }
  extension <- switch(language, "C++"=".cpp", C=".c", Fortran=".f", F95=".f95",
                                ObjectiveC=".m", "ObjectiveC++"=".mm")
  libCFile <- sub(".EXT$", extension, libCFile)

  ## Write the code to the temp file for compilation
  write(code, libCFile)

  ## Compile the code using the running version of R if several available
  if ( file.exists(libLFile) ) file.remove( libLFile )
  if ( file.exists(libLFile2) ) file.remove( libLFile2 )

  setwd(dirname(libCFile))
  errfile <- paste( basename(libCFile), ".err.txt", sep = "" )
  cmd <- paste(R.home(component="bin"), "/R CMD SHLIB ", basename(libCFile), " 2> ", errfile, sep="")
  if (verbose) cat("Compilation argument:\n", cmd, "\n")
  compiled <- system(cmd, intern=!verbose)
  errmsg <- readLines( errfile )
  unlink( errfile )
  writeLines( errmsg )
  setwd(wd)

  if ( !file.exists(libLFile) && file.exists(libLFile2) ) libLFile <- libLFile2
  if ( !file.exists(libLFile) ) {
    cat("\nERROR(s) during compilation: source code errors or compiler configuration errors!\n")
    cat("\nProgram source:\n")
    code <- strsplit(code, "\n")
    for (i in 1:length(code[[1]])) cat(format(i,width=3), ": ", code[[1]][i], "\n", sep="")
    stop( paste( "Compilation ERROR, function(s)/method(s) not created!", paste( errmsg , collapse = "\n" ) ) )
  }
  return( libLFile )
}
