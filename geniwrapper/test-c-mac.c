#include <stdio.h>
#include <stdlib.h>
#include "MinimalGenI_stub.h"

char* slurp(const char* filename);

extern void __stginit_MinimalGenI(void);

void HsStart()
{
   int argc = 1;
   char* argv[] = {"sortOfGHC", NULL}; // argv must end with NULL

   // Initialize Haskell runtime
   char** args = argv;
   hs_init(&argc, &args);

   // Tell Haskell about all root modules
   hs_add_root(__stginit_MinimalGenI);
}

void HsEnd()
{
   hs_exit();
}

int main(int argc, char *argv[]) {
  char *macros_fn;
  char *lexicon;
  char *test_sem;
  char *result;
  void *geni_st;

  HsStart();
  if (argc < 4) {
    printf("Usage: %s <macros-file> <lexicon-file> <sem-file>\n", argv[0]);
    return 2;
  }

  macros_fn=argv[1];
  lexicon=slurp(argv[2]);
  test_sem=slurp(argv[3]);
  
  // go!
  geni_st=geni_init(macros_fn);
  if ( geni_st == NULL ) {
    fprintf(stderr, "Could not initialise GenI wrapper");
    exit(1);
  }
  result=geni_realize(geni_st, lexicon, test_sem);
  printf("%s", result);
  geni_free(result);

  free(test_sem);
  free(lexicon);

  HsEnd();
}

// this allocates a string you must free
char* slurp(const char* filename) {
  char *contents;
  FILE *fp;

  fp = fopen(filename, "r");
  if (fp == NULL) {
    fprintf(stderr, "Could not open %s", filename);
    exit(1);
  }
  fseek(fp, 0L, SEEK_END);
  long s = ftell(fp);
  rewind(fp);
  contents = malloc(s);
  if ( fp == NULL ) {
    fprintf(stderr, "Could not read %s", filename);
    exit(1);
  }
  fread(contents, s, 1, fp);
  fclose(fp);
  fp = NULL;
  return contents;
}
