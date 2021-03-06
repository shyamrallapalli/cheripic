#!/usr/bin/env ruby

module Cheripic

  # A command line option and processing object to handle input options
  #
  # @!attribute [rw] options
  #   @return [Hash] a hash of trollop option names as keys and user or default setting as values
  class Cmd

    require 'trollop'
    require 'pathname'
    require 'ostruct'

    attr_accessor :options

    # creates a Cmd object using input string entry
    # @param args [String]
    def initialize(args)
      @options = parse_arguments(args)
      check_arguments
    end

    # method to check input command string and run appropriate
    # method of the object (help or examples or parsing arguments)
    # @param args [String]
    def parse_arguments(args)
      Trollop::with_standard_exception_handling argument_parser do
        if args.empty? || args.include?('-h') || args.include?('--help')
          raise Trollop::HelpNeeded
        elsif args.include?('--examples')
          print_examples
        end
        argument_parser.parse args
      end
    end

    # trollop argument_parser for input args string and
    # @return [Hash] a hash of trollop option names as keys and user or default setting as values
    def argument_parser
      cmds = self
      Trollop::Parser.new do
        version Cheripic::VERSION
        banner cmds.help_message
        opt :assembly, 'Assembly file in FASTA format',
            :short => '-f',
            :type => String
        opt :input_format, 'bulk and parent alignment file format types - set either pileup or bam or vcf',
            :short => '-F',
            :type => String,
            :default => 'pileup'
        opt :mut_bulk, 'Pileup or sorted BAM file alignments from mutant/trait of interest bulk 1',
            :short => '-a',
            :type => String
        opt :mut_bulk_vcf, 'vcf file for variants from mutant/trait of interest bulk 1',
            :type => String,
            :default => ''
        opt :bg_bulk, 'Pileup or sorted BAM file alignments from background/wildtype bulk 2',
            :short => '-b',
            :type => String
        opt :bg_bulk_vcf, 'vcf file for variants from background/wildtype bulk 2',
            :type => String,
            :default => ''
        opt :output, 'custom name tag to include in the output file name',
            :default => 'cheripic_results'
        opt :loglevel, 'Choose any one of "info / warn / debug" level for logs generated',
            :default => 'info'
        opt :hmes_adjust, 'factor added to snp count of each contig to adjust for hme score calculations',
            :type => Float,
            :default => 0.5
        opt :htlow, 'lower level for categorizing heterozygosity',
            :type => Float,
            :default => 0.25
        opt :hthigh, 'high level for categorizing heterozygosity',
            :type => Float,
            :default => 0.75
        opt :mindepth, 'minimum read depth at a position to consider for variant calls',
            :type => Integer,
            :default => 6
        opt :max_d_multiple, "multiplication factor for average coverage to calculate maximum read coverage
if set zero no calculation will be made from bam file.\nsetting this value will override user set max depth",
            :type => Integer,
            :default => 5
        opt :maxdepth, 'maximum read depth at a position to consider for variant calls
if set to zero no user max depth will be used',
            :type => Integer,
            :default => 0
        opt :min_non_ref_count, 'minimum read depth supporting non reference base at each position',
            :type => Integer,
            :default => 3
        opt :min_indel_count_support, 'minimum read depth supporting an indel at each position',
            :type => Integer,
            :default => 3
        opt :ambiguous_ref_bases, 'including variant at completely ambiguous bases in the reference',
            :type => String,
            :default => 'false'
        opt :mapping_quality, 'minimum mapping quality of read covering the position',
            :short => '-q',
            :type => Integer,
            :default => 20
        opt :base_quality, 'minimum base quality of bases covering the position',
            :short => '-Q',
            :type => Integer,
            :default => 15
        opt :noise, 'praportion of reads for a variant to conisder as noise',
            :type => Float,
            :default => 0.1
        opt :cross_type, 'type of cross used to generated mapping population - back or out',
            :type => String,
            :default => 'back'
        opt :use_all_contigs, 'option to select all contigs or only contigs containing variants for analysis',
            :type => String,
            :default => 'false'
        opt :include_low_hmes, 'option to include or discard variants from contigs with
low hme-score or bfr score to list in the final output',
            :type => String,
            :default => 'false'
        opt :polyploidy, 'Set if the data input is from polyploids',
            :type => String,
            :default => 'false'
        opt :mut_parent, 'Pileup or sorted BAM file alignments from mutant/trait of interest parent',
            :short => '-p',
            :type => String,
            :default => ''
        opt :bg_parent, 'Pileup or sorted BAM file alignments from background/wildtype parent',
            :short => '-r',
            :type => String,
            :default => ''
        opt :repeats_file, 'repeat masker output file for the assembly ',
            :short => '-R',
            :type => String,
            :default => ''
        opt :bfr_adjust, 'factor added to hemi snp frequency of each parent to adjust for bfr calculations',
            :type => Float,
            :default => 0.05
        opt :sel_seq_len, 'sequence length to print from either side of selected variants',
            :type => Integer,
            :default => 50
        opt :examples, 'shows some example commands with explanation'
      end
    end

    # help message to display from command line
    def help_message
      msg = <<-EOS

      Cheripic v#{Cheripic::VERSION.dup}
      Authors: Shyam Rallapalli and Dan MacLean

      Description: Candidate mutation and closely linked marker selection for non reference genomes
      Uses bulk segregant data from non-reference sequence genomes

      Inputs:
      1. Needs a reference fasta file of asssembly use for variant analysis
      2. Pileup/Bam files for mutant (phenotype of interest) bulks and background (wildtype phenotype) bulks
      3. If providing bam files, you have to include vcf files for the respective bulks
      4. If polyploid species, include pileup/bam files from one or both parents

      USAGE:
      cheripic <options>

      OPTIONS:

      EOS
      msg.split("\n").map{ |line| line.lstrip }.join("\n")
    end

    # examples to display from command line
    def print_examples
      msg = <<-EOS

      Cheripic v#{Cheripic::VERSION.dup}
      Authors: Shyam Rallapalli and Dan MacLean

      EXAMPLE COMMANDS:
        1. cheripic -f assembly.fa -a mutbulk.pileup -b bgbulk.pileup --output=cheripic_output
        2. cheripic --assembly assembly.fa --mut-bulk mutbulk.pileup --bg-bulk bgbulk.pileup
              --mut-parent mutparent.pileup --bg-parent bgparent.pileup --polyploidy true --output cheripic_results
        3. cheripic --assembly assembly.fa --mut-bulk mutbulk.pileup --bg-bulk bgbulk.pileup
              --mut-parent mutparent.pileup --bg-parent bgparent.pileup --polyploidy true
              --no-only-frag-with-vars --no-filter-out-low-hmes --output cheripic_results
        4. cheripic -h or cheripic --help
        5. cheripic -v or cheripic --version

      EOS
      puts msg.split("\n").map{ |line| line.lstrip }.join("\n")
      exit(0)
    end

    # calls other methods to check if command line inputs are valid
    def check_arguments
      convert_boolean_strings
      check_output
      check_log_level
      check_input_entry
      check_input_types
    end

    # convert true or false options to boolean
    def convert_boolean_strings
      %i{ambiguous_ref_bases use_all_contigs include_low_hmes polyploidy}.each do | symbol |
        if @options.key?(symbol)
          @options[symbol] = @options[symbol] == 'false' ? false : true
        end
      end
    end

    # set file given option to false if input is nil or None or ''
    def check_input_entry
      %i{assembly mut_bulk bg_bulk mut_bulk_vcf bg_bulk_vcf mut_parent bg_parent repeats_file}.each do | symbol |
        if @options.key?(symbol)
          if @options[symbol] == 'None'
            param = (symbol.to_s + '_given').to_sym
            @options[symbol] = ''
            @options.delete(param)
          end
        end
      end
    end

    # checks input files based on bulk file type
    def check_input_types
      inputfiles = {}
      inputfiles[:required] = %i{assembly mut_bulk}
      inputfiles[:optional] = %i{bg_bulk}
      if @options[:input_format] == 'bam'
        inputfiles[:required] << %i{mut_bulk_vcf}
        inputfiles[:optional] << %i{bg_bulk_vcf}
      end
      if @options[:polyploidy]
        inputfiles[:either] = %i{mut_parent bg_parent}
      end
      check_input_files(inputfiles)
    end

    # checks if input files are valid
    def check_input_files(inputfiles)
      inputfiles.each_key do | type |
        inputfiles[type].flatten!
        check = 0
        inputfiles[type].each do | symbol |
          if @options[symbol] == nil or @options[symbol] == ''
            if type == :required
              raise CheripicArgError.new "Options #{inputfiles}, all must be specified. Try --help for further help."
            end
          else
            file = @options[symbol]
            if symbol == :bg_bulk or symbol == :bg_bulk_vcf
              if file.include? ','
                @options[symbol] = []
                file.split(',').each do | infile |
                  @options[symbol] << File.expand_path(infile)
                  file_exist?(symbol, infile)
                end
              end
            else
              @options[symbol] = File.expand_path(file)
              file_exist?(symbol, file)
            end
            check = 1
          end
        end
        if type == :either and check == 0
          raise CheripicArgError.new "One of the options #{inputfiles}, must be specified. " +
                                       'Try --help for further help.'
        end
      end
    end

    def file_exist?(symbol, file)
      # checks if a given file exists
      unless File.exist?(file)
        raise CheripicIOError.new "#{symbol} file, #{file} does not exist!"
      end
    end

    # checks if files with output tag name already exists
    def check_output
      if (@options[:output].split('') & %w{# / : * ? ' < > | & $ ,}).any?
        raise CheripicArgError.new 'please choose a name tag that contains ' +
                                       'alphanumeric characters, hyphen(-) and underscore(_) only'
      end
      @options[:hmes_frags] = "#{@options[:output]}_selected_hme_variants.txt"
      @options[:bfr_frags] = "#{@options[:output]}_selected_bfr_variants.txt"
      [@options[:hmes_frags], @options[:bfr_frags]].each do | file |
        if File.exist?(file)
          raise CheripicArgError.new "'#{file}' file exists " +
                                         'please choose a different name tag to be included in the output file name'
        end
      end
    end

    # checks and sets logger level
    def check_log_level
      unless %w(error info warn debug).include?(@options[:loglevel])
        raise CheripicArgError.new "Loglevel #{@options[:loglevel]} is not valid. " +
                                       'It must be one of: error, info, warn, debug.'
      end
      logger.level = Yell::Level.new @options[:loglevel].to_sym
    end

    # Initializes an Implementer object using input options
    # and calls run method of the Implementer to start the pipeline
    # A hash of trollop option names as keys and user or default
    # setting as values is passed to Implementer object
    def run
      @options[:hmes_frags] = File.expand_path @options[:hmes_frags]
      @options[:bfr_frags] = File.expand_path @options[:bfr_frags]
      analysis = Implementer.new(@options)
      analysis.run
    end

  end # Cmd

end # Cheripic
