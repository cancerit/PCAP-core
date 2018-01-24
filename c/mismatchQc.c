/*       LICENCE
* PCAP - NGS reference implementations and helper code for mapping (originally part of ICGC/TCGA PanCancer)
# Copyright (C) 2014-2018 Genome Research Ltd.
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
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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
char* prog_id="PCAP-core-mismatchQC";
char* prog_name="mismatchQc";
char* prog_desc="Marks a read as QCFAIL where the mismatch rate higher than the threshold";
char* prog_cl = NULL;
float mismatch_frac = 0.05;
int debug=0;
const char mm_tag[2] = "mm";
const char tag_type = 'A';
const char *MD_TAG = "MD";
const char YES = 'Y';
long long int marked_count = 0;
#define _cop(c) ((c)&BAM_CIGAR_MASK)
/*
  Ignore mate unmapped,
  read unmapped,
  supplementary alignment,
  not primary alignment,
  read fails platform/vendor quality checks,
  read is PCR or optical duplicate
*/
const int BAD_FLAGS = BAM_FUNMAP | BAM_FMUNMAP | BAM_FQCFAIL | BAM_FDUP | BAM_FSECONDARY | BAM_FSUPPLEMENTARY;

enum rw_opts {
  W_CRAM        = 1,
};

void print_version (int exit_code){
  printf ("%s\n",VERSION);
	exit(exit_code);
}

int check_exist(char *fname){
	FILE *fp;
	if((fp = fopen(fname,"r"))){
		fclose(fp);
		return 1;
	}
	return 0;
}

void print_usage (int exit_code){

	printf ("Usage: mismatchQc -i file -o file [-h] [-v]\n\n");
  printf ("Marks reads \n");
  printf ("-i --input                  [bc]ram File path to read input [stdin].\n");
  printf ("-o --output                 Path to output [stdout].\n\n");
  printf ("Optional:\n");
  printf ("-@ --threads                File path to reference index (.fai) file.\n");
  printf ("-C --cram                   Use CRAM compression for output [default: bam].\n");
  printf ("-x --index                  Generate an index alongside output file (invalid when output is to stdout).\n");
  printf ("-t --mismatch-threshold     Mismatch threshold for marking read as QC fail [float](default: %f).\n",mismatch_frac);
  printf ("-r --reference              load CRAM references from the specificed fasta file instead of @SQ headers when writing a CRAM file\n");
  printf ("-l --compression-level      0-9: set zlib compression level.\n\n");
	printf ("Other:\n");
	printf ("-h --help      Display this usage information.\n");
  printf ("-d --debug     Turn on debug mode.\n");
	printf ("-v --version   Prints the version number.\n\n");
  exit(exit_code);
}

void options(int argc, char *argv[]){
  strcat(prog_cl,argv[0]);
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
            {"mismatch-threshold",required_argument,0,'t'},
            { NULL, 0, NULL, 0}

 }; //End of declaring opts

 int index = 0;
 int iarg = 0;

 //Iterate through options
  while((iarg = getopt_long(argc, argv, "t:l:i:o:r:@:Cvxdh", long_opts, &index)) != -1){
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

     case 't':
      if(sscanf(optarg, "%f", &mismatch_frac) != 1){
         sentinel("Error parsing -t argument '%s'. Should be a 1.0 >= float >= 0.0.",optarg);
      }
      strcat(prog_cl," -t ");
      strcat(prog_cl,optarg);
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

   return;
  error:
    return;
}

float infer_mis_match_rate(bam1_t *b){
  int match = 0;
  int mismatch = 0;
  int n_del = 0;
  int n_insert = 0;
  int totalmap = 0;
  float return_val = 0;
  uint8_t *tag_val = bam_aux_get(b,MD_TAG);
  check(tag_val!=NULL,"Error retrieving md tag for read.");
  if(tag_val==NULL){ //No MD tag present
    return return_val;
  }else{
    char *md_val = bam_aux2Z(tag_val);
    check(md_val!=NULL,"Error retrieving md tag value for read.");
    //Iterate through string until we find a non number character
    int i=0;
    for(i=0;i<strlen(md_val);i++){
      if(!isdigit(md_val[i])){ // Not a digit therefor we have a deletion or a mismatch
        if(md_val[i]=='^'){//Deletion
          mismatch = mismatch+1;
          //Iterate to the next number as all following bases are the deleted bases
          while(isalpha(md_val[i+1]) && i<strlen(md_val)){
            i++;
          }
        }else{//Mismatch
          mismatch = mismatch+1;
        }
      }else if(isdigit(md_val[i])){
        //got a digit so build the number up.
        char num[5] = "\0\0\0\0\0";
        int index = 0;
        while(isdigit(md_val[i]) && i<strlen(md_val)){
          num[index] = md_val[i];
          index++;
          i++;
        }
        i--;
        match = match + atoi(num);
      }
    }
    //Now iterate through the cigar to calculate accurately with indels and non indels
    uint32_t *cigar = bam_get_cigar(b);
    //iterate through each cigar operation
    int j=0;
    for(j=0;j<b->core.n_cigar;j++){
      int op = _cop(cigar[j]);
      if(op == BAM_CINS) n_insert++;
      if(op == BAM_CDEL) n_del++;
    }

    totalmap =  match + mismatch - n_del;
    return_val = ((float)mismatch + (float)n_insert)/(float)totalmap;
  }
  return return_val;


error:
  return -1;
}

int checkMismatchStatus(bam1_t **b){
  if ((*b)->core.flag & BAD_FLAGS) return 0; //Ignore bad flags
  float mm_rate = infer_mis_match_rate(*b);
  check(mm_rate>=0,"Error inferring mismatch rate for read.");
  if(mm_rate>mismatch_frac){
    //Add QC fail flag
    (*b)->core.flag = (*b)->core.flag | BAM_FQCFAIL;
    //Add mm tag
    int chk = bam_aux_append(*b, mm_tag, tag_type, sizeof(YES), (uint8_t *) &YES);

    check(chk==0,"Error adding mismatch tag to read %s.",bam_get_qname(*b));
    uint8_t *p;
    if((p = bam_aux_get(*b, mm_tag)) && bam_aux2A(p)!=YES){
     sentinel("Error adding new tag to read %s.",bam_get_qname(*b));
    }
    marked_count = marked_count+1;
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
  char modew[800];
  bam1_t *b = NULL;
  prog_cl = malloc(sizeof(char)*2000);
  check_mem(prog_cl);
  options(argc,argv);

  time_t time_start = time(NULL);

  //Open bam file as object
  input = hts_open(input_file,"r");
  check(input != NULL, "Error opening hts file for reading '%s'.",input_file);

  //Read header from bam file
  head = sam_hdr_read(input);
  check(head != NULL, "Error reading header from opened hts file '%s'.",input_file);
  //Setup output. Either match input format or bam/cram depending on commandline flag

  strcpy(modew, "w");
  strcat(modew, "b");
  if (clevel >= 0 && clevel <= 9) sprintf(modew + 1, "%d", clevel);
  if(wflags & W_CRAM){
    strcat(modew, "c");
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

  //Headers and setup now sorted. Now we can perform mismatch QC
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
    int rd_check = 0;
    rd_check = checkMismatchStatus(&b);
    check(rd_check==0,"Error checking mismatch status of reads.");
    int res = sam_write1(output,new_head,b);
    check(res>=0,"Error writing read to output file.");
  }

  int out = hts_close(output);
  check(out>=0,"Error closing output file.");
  if(debug==1) fprintf(stderr,"Processed %lld reads in total, marked %lld as qc_failed.\n",count,marked_count);
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
