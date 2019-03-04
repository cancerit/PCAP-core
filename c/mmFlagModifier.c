/*       LICENCE
* PCAP - NGS reference implementations and helper code for mapping (originally part of ICGC/TCGA PanCancer)
# Copyright (C) 2014-2019 Genome Research Ltd.
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public License
* as published by the Free Software Foundation; either version 2
* of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program; if not see:
*   http://www.gnu.org/licenses/gpl-2.0.html
*/

#include <getopt.h>
#include "dbg.h"
#include "cram/cram.h"
#include "htslib/thread_pool.h"
#include "bam_access.h"

char *input_file = NULL;
char *output_file = NULL;
char *fn_ref = NULL;
int nthreads = 0;
int wflags = 0;
int clevel = -1;
int is_index = 0;
char* prog_id="PCAP-core-mmFlagModifier";
char* prog_name="mmFlagModifier";
char* prog_desc="Removes or reinstates the QC vendor fail flag in the presence of the mismatch QC fail tag";
char* prog_cl = NULL;
int debug=0;
const char mm_tag[2] = "mm";
const char tag_type = 'A';
const char YES = 'Y';
long long int marked_count = 0;

enum rw_opts {
  W_CRAM        = 1,
  RW_REMOVE     = 2,
  RW_REPLACE    = 4,
};

int check_exist(char *fname){
	FILE *fp;
	if((fp = fopen(fname,"r"))){
		fclose(fp);
		return 1;
	}
	return 0;
}

void print_version (int exit_code){
  printf ("%s\n",VERSION);
	exit(exit_code);
}

void print_usage (int exit_code){

  printf ("Usage: mmFlagModifier -i file -o file [-h] [-v]\n\n");
  printf ("-i --input                  [bc]ram File path to read input [stdin].\n");
  printf ("-o --output                 Path to output [stdout].\n\n");
  printf ("-m --remove                 Remove Vendor fail Qc flag where mmQC tag is present\n");
  printf ("-p --replace                Reinstate Vendor fail Qc flag where mmQC tag is present\n\n");
  printf ("Optional:\n");
  printf ("-@ --threads                number of BAM/CRAM compression threads.\n");
  printf ("-C --cram                   Use CRAM compression for output [default: bam].\n");
  printf ("-x --index                  Generate an index alongside output file (invalid when output is to stdout).\n");
  printf ("-r --reference              load CRAM references from the specificed fasta file instead of @SQ headers when writing a CRAM file\n");
  printf ("-l --compression-level      0-9: set zlib compression level.\n\n");
  printf ("Other:\n");
  printf ("-h --help      Display this usage information.\n");
  printf ("-d --debug     Turn on debug mode.\n");
  printf ("-v --version   Prints the version number.\n\n");
  exit(exit_code);
}

int options(int argc, char *argv[]){
  strcat(prog_cl, argv[0]);
  const struct option long_opts[] =
  {
            {"version",no_argument, 0, 'v'},
            {"help",no_argument,0,'h'},
            {"debug",no_argument,0,'d'},
            {"input",required_argument,0,'i'},
            {"output",required_argument,0,'o'},
            {"cram",no_argument,0,'C'},
            {"index",no_argument,0,'x'},
            {"threads",required_argument,0,'@'},
            {"compression-level",required_argument,0,'l'},
            {"reference",required_argument,0,'r'},
            {"remove",no_argument,0,'m'},
            {"replace",no_argument,0,'p'},
            { NULL, 0, NULL, 0}

 }; //End of declaring opts

 int index = 0;
 int iarg = 0;

 //Iterate through options
  while((iarg = getopt_long(argc, argv, "l:i:o:r:@:Cvxdhmp", long_opts, &index)) != -1){
    switch(iarg){
      case 'i':
        input_file = optarg;
        break;

      case 'o':
        output_file = optarg;
        break;

      case 'h':
        print_usage(0);
        break;

      case 'v':
        print_version(0);
        break;

      case 'd':
        debug=1;
        break;

      case '@':
        if(sscanf(optarg, "%i", &nthreads) != 1){
          sentinel("Error parsing -@ nThreads) argument '%s'. Should be an integer",optarg);
        }
        strcat(prog_cl," -@ ");
        strcat(prog_cl,optarg);
        break;

      case 'C':
        wflags |= W_CRAM;
        strcat(prog_cl," -C");
        break;

      case 'x':
        is_index = 1;
        strcat(prog_cl," -x");
        break;

      case 'l':
        if(sscanf(optarg, "%i", &clevel) != 1){
          sentinel("Error parsing -l (compression level) argument '%s'. Should be an integer",optarg);
        }
        strcat(prog_cl," -l ");
        strcat(prog_cl,optarg);
        break;

      case 'r':
        fn_ref = optarg;
        strcat(prog_cl," -f ");
        strcat(prog_cl,fn_ref);
        break;

      case 'm':
        wflags |= RW_REMOVE;
        strcat(prog_cl," -m");
        break;

      case 'p':
        wflags |= RW_REPLACE;
        strcat(prog_cl," -p");
        break;

      case '?':
        print_usage (1);
        break;

      default:
        print_usage (1);

    }; // End of args switch statement

  }//End of iteration through options
  //Do some checking to ensure required arguments were passed and are accessible files
  if (input_file==NULL || strcmp(input_file,"/dev/stdin")==0) {
    input_file = "-";   // htslib recognises this as a special case
  }
  strcat(prog_cl," -i ");
  strcat(prog_cl,input_file);
  if (strcmp(input_file,"-") != 0) {
    if(check_exist(input_file) != 1){
      printf("Input file (-i) %s does not exist.\n",input_file);
      print_usage(1);
    }
  }

  if (output_file==NULL || strcmp(output_file,"/dev/stdout")==0) {
    output_file = "-";   // we recognise this as a special case
    check(is_index==0,"Cannot output an index file when stdout is used for output.");
  }
  strcat(prog_cl," -o ");
  strcat(prog_cl,output_file);


  if((wflags & RW_REMOVE) && (wflags & RW_REPLACE)){//Remove mode
    printf("Cannot set both remove and replace modes at the same time.\n");
    print_usage(1);
  }

  if(!(wflags & RW_REMOVE) && !(wflags & RW_REPLACE)){
    printf("Please choose either remove or replace mode.\n");
    print_usage(1);
  }

  return 0;

  error:
    return 1;
}

int main(int argc, char *argv[]){
  htsFile *input = NULL;
  htsFile *output = NULL;
  hts_idx_t *index = NULL;
  bam_hdr_t *head = NULL;
  bam_hdr_t *new_head = NULL;
  bam1_t *b = NULL;
  time_t time_start = time(NULL);
  char modew[800];

  prog_cl = malloc(sizeof(char)*2000);
  check_mem(prog_cl);

  int problem = options(argc,argv);
  check(problem==0,"Error parsing options.");

  //Open bam file as object
  input = hts_open(input_file,"r");
  check(input != NULL, "Error opening hts file for reading '%s'.",input_file);

  //Read header from bam file
  head = sam_hdr_read(input);
  check(head != NULL, "Error reading header from opened hts file '%s'.",input_file);

  //Setup output. Either match input format or bam/cram depending on commandline flag
  strcpy(modew, "w");
  if (clevel >= 0 && clevel <= 9) sprintf(modew + 1, "%d", clevel);
  if(wflags & W_CRAM){
    strcat(modew, "c");
  }else{
    strcat(modew, "b");
  }
  if(debug==1) fprintf(stderr,"Outputting data to %s using mode %s.\n",output_file,modew);
  output = hts_open(output_file,modew);
  check(output != NULL, "Error opening hts file for writing '%s' in mode %s.",output_file,modew);

  //Add program line to header
  SAM_hdr *cram_head = bam_header_to_cram(head);
  check(cram_head != NULL,"Error converting bam header to cram for PG add.");
  int chk_h = sam_hdr_add_PG(cram_head,prog_id,"CL",prog_cl,"DS",prog_desc,"VN",VERSION,NULL);
  check(chk_h==0,"Error adding PG line to header.");
  //Reference setup if CRAM output
  if (wflags & W_CRAM) {
    int ret;
    // Parse input header and use for CRAM output
    output->fp.cram->header = cram_head;

    // Create CRAM references arrays
    if (fn_ref)
        ret = cram_set_option(output->fp.cram, CRAM_OPT_REFERENCE, fn_ref);
    else
        // Attempt to fill out a cram->refs[] array from @SQ headers
        ret = cram_set_option(output->fp.cram, CRAM_OPT_REFERENCE, NULL);

    check(ret == 0, "Error setting CRAM reference file for writing");
  }

  //Set threads if required for input and output
  // Create and share the thread pool
  htsThreadPool p = {NULL, 0};
  if (nthreads > 0) {
    p.pool = hts_tpool_init(nthreads);
    check(p.pool != NULL,"Error creating thread pool");
    hts_set_opt(input,  HTS_OPT_THREAD_POOL, &p);
    hts_set_opt(output, HTS_OPT_THREAD_POOL, &p);
  }

  new_head = cram_header_to_bam(cram_head);
  int hd_chk = sam_hdr_write(output, new_head);
  check(hd_chk!=-1,"Error writing header to output file.");

  //Headers and setup now sorted. Now we can perform either removal or addition of QCFLag
  long long int count = 0;
  time_start = time(NULL);

  //Iterate through each read in bam file.
  b = bam_init1();
  int ret;
  while((ret = sam_read1(input, new_head, b)) >= 0){
    count = count+1;
    if(debug == 1 && count % 10000000 == 0){ //Every 10 Mil reads
      time_t curr_time = time(NULL);
      double elapsed_time = difftime(curr_time,time_start);
      fprintf(stderr,
        "processed %lld * 10 Million reads, %.1f seconds for this 10 million.\n",
                                                  count/10000000,elapsed_time);
      time_start = time(NULL);
    }
    //Check to see if the read has the mm tag required.
    int has_tag = 0;
    has_tag = check_mm_tag(b); 
    check(has_tag>=0,"Error checking for mm tag in read.");
    if(has_tag){
      marked_count++;
      if(wflags & RW_REMOVE){
        b->core.flag -= BAM_FQCFAIL;
      }else if(wflags & RW_REPLACE){
        if(!(b->core.flag & BAM_FQCFAIL)){
          b->core.flag += BAM_FQCFAIL;
        }
      }
    }
    int res = sam_write1(output,new_head,b);
    check(res>=0,"Error writing read to output file.");
  }//End of iteration through each read in the xam file
  
  
  int out = hts_close(output);
  check(out>=0,"Error closing output file.");
  if(debug==1) fprintf(stderr,"Processed %lld reads in total, modified %lld flags.\n",count,marked_count);
  //Finally we create the index file
  if(is_index==1){
    if(debug==1) fprintf(stderr,"Building index.");
    int chk_idx = sam_index_build(output_file,NULL);
    check(chk_idx==0,"Error writing index file.");
  }

  if(debug==1) fprintf(stderr,"Done.\n");

  bam_destroy1(b);
  bam_hdr_destroy(head);
  bam_hdr_destroy(new_head);
  sam_hdr_free(cram_head);
  free(prog_cl);
  int in = hts_close(input);
  check(in>=0,"Error closing input file.");

  if (p.pool) hts_tpool_destroy(p.pool);

  return 0;

  error:
    if(b) bam_destroy1(b);
    if(head) bam_hdr_destroy(head);
    if(new_head) bam_hdr_destroy(new_head);
    if(input) hts_close(input);
    if(cram_head) sam_hdr_free(cram_head);
    if(prog_cl) free(prog_cl);
    if(output) hts_close(output);
    if (p.pool) hts_tpool_destroy(p.pool);
    return 1;
}

int check_mm_tag(bam1_t *b){
  uint8_t *p;
  if((p = bam_aux_get(b, mm_tag)) && bam_aux2A(p)==YES){
    return 1;
  }
  return 0;
}
