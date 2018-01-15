/*       LICENCE
* PCAP - NGS reference implementations and helper code for mapping (originally part of ICGC/TCGA PanCancer)
# Copyright (C) 2014-2018 OWNER HERE
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

static char *input_file = NULL;
static char *output_file = NULL;
int nthreads = 0;
char *is_cram=0;

void print_version (int exit_code){
  printf ("%s\n",VERSION);
	exit(exit_code);
}

void print_usage (int exit_code){

	printf ("Usage: mismatchQc -i file -o file [-h] [-v]\n\n");
  printf ("-i --input     [bc]ram File path to read input [stdin].\n");
  printf ("-o --output    Path to output [stdout].\n\n");
  printf ("Optional:\n");
  printf ("-@ --threads   File path to reference index (.fai) file.\n");
  printf ("-C --cram      Use CRAM compression for output [default: bam].\n\n");
	printf ("Other:\n");
	printf ("-h --help      Display this usage information.\n");
	printf ("-v --version   Prints the version number.\n\n");
  exit(exit_code);
}

void options(int argc, char *argv[]){
  const struct option long_opts[] =
  {
            {"version",no_argument, 0, 'v'},
            {"help",no_argument,0,'h'},
            {"input",required_argument,0,'i'},
            {"output",required_argument,0,'o'},
            {"cram",no_argument,0,'C'},
            {"threads",required_argument,0,'@'}
            { NULL, 0, NULL, 0}

 }; //End of declaring opts

 int index = 0;
 int iarg = 0;

 //Iterate through options
  while((iarg = getopt_long(argc, argv, "i:o:r:@:Cvh", long_opts, &index)) != -1){
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
   if (strcmp(input_file,"-") != 0) {
     if(check_exist(input_file) != 1){
   	  printf("Input file (-i) %s does not exist.\n",input_file);
   	  print_usage(1);
     }
   }
   if (output_file==NULL || strcmp(output_file,"/dev/stdout")==0) {
    output_file = "-";   // we recognise this as a special case
   }

   return;
}

int main(int argc, char *argv[]){
  options(argc,argv);
  htsFile *input = NULL;
  htsFile *output = NULL;
	bam_hdr_t *head = NULL;

  //Open bam file as object
  input = hts_open(input_file,"r");
  check(input != NULL, "Error opening hts file for reading '%s'.",input_file);

  //Setup output. Either match input format or bam/cram depending on commandline flag
  //Set threads if required for input and output

  //Read header from bam file
  head = sam_hdr_read(input);
  check(head != NULL, "Error reading header from opened hts file '%s'.",input_file);

  //Add program line to header
  //Setup output. Either match input format or bam/cram depending on commandline flag

  fprintf(stderr,"RUNNING PROGRAM");


  bam_hdr_destroy(head);
  hts_close(input);

  return 0;

  error:
    if(head) bam_hdr_destroy(head);
    if(input) hts_close(input);
    return 1;
}
