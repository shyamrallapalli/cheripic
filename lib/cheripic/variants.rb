# encoding: utf-8
require 'bio'
require 'forwardable'

module Cheripic

  class VariantsError < CheripicError; end

  class Variants

    include Enumerable
    extend Forwardable
    def_delegators :@assembly, :each, :each_key, :each_value, :size, :length, :[]
    attr_accessor :assembly, :has_run, :pileups, :hmes_frags, :bfr_frags

    def initialize(options)
      @params = options
      @assembly = {}
      @pileups = {}
      Bio::FastaFormat.open(@params.assembly).each do |entry|
        if entry.seq.length == 0
          logger.error "No sequence found for entry #{entry.entry_id}"
          raise VariantsError
        end
        contig = Contig.new(entry)
        if @assembly.key?(contig.id)
          logger.error "fasta id already found in the file for #{contig.id}"
          logger.error 'make sure there are no duplicate entries in the fasta file'
          raise VariantsError
        end
        @assembly[contig.id] = contig
        @pileups[contig.id] = ContigPileups.new(contig.id)
      end
    end

    # Read and store pileup data for each bulk and parents
    #
    def analyse_pileups
      set_defaults
      @bg_bulk ||= @params.bg_bulk
      @mut_parent ||= @params.mut_parent
      @bg_parent ||= @params.bg_parent

      %i{mut_bulk bg_bulk mut_parent bg_parent}.each do | input |
        infile = @params[input]
        if infile != ''
          extract_pileup(infile, input)
        end
      end

      @has_run = true
    end

    def set_defaults
      @bg_bulk = ''
      @mut_parent = ''
      @bg_parent = ''
    end

    def extract_pileup(pileupfile, sym)
      # read mpileup file and process each variant
      File.foreach(pileupfile) do |line|
        pileup = Pileup.new(line)
        if pileup.is_var
          contig_obj = @pileups[pileup.ref_name]
          contig_obj.send(sym).store(pileup.pos, pileup)
        end
      end
    end

    def compare_pileups
      unless defined?(@has_run)
        self.analyse_pileups
      end
      @assembly.each_key do | id |
        contig = @assembly[id]
        # extract parental hemi snps for polyploids before bulks are compared
        if @mut_parent != '' or @bg_parent != ''
          @pileups[id].hemisnps_in_parent
        end
        contig.hm_pos, contig.ht_pos, contig.hemi_pos = @pileups[id].bulks_compared
      end
    end

    def hmes_frags
      unless defined?(@hmes_frags)
        @hmes_frags = select_contigs(:hmes)
      end
      @hmes_frags
    end

    def bfr_frags
      unless defined?(@bfr_frags)
        @bfr_frags = select_contigs(:bfr)
      end
      @bfr_frags
    end

    def select_contigs(ratio_type)
      selected_contigs ={}
      only_frag_with_vars = Options.params.only_frag_with_vars
      @assembly.each_key do | frag |
        if only_frag_with_vars and ratio_type == :hmes
          # selecting fragments which have a variant
          numhm = @assembly[frag].hm_num
          numht = @assembly[frag].ht_num
          if numht + numhm > 2 * Options.params.hmes_adjust
            selected_contigs[frag] = @assembly[frag]
          end
        elsif only_frag_with_vars and ratio_type == :bfr
          # in polyploidy scenario selecting fragments with at least one bfr position
          numbfr = @assembly[frag].hemi_num
          if numbfr > 0
            selected_contigs[frag] = @assembly[frag]
          end
        else
          selected_contigs[frag] = @assembly[frag]
        end
      end
      selected_contigs = filter_contigs(selected_contigs, ratio_type)
      if only_frag_with_vars
        logger.info "Selected #{selected_contigs.length} out of #{@assembly.length} fragments with #{ratio_type.to_s} score\n"
      else
        logger.info "No filtering was applied to fragments\n"
      end
      selected_contigs
    end

    def filter_contigs(selected_contigs, ratio_type)
      filter_out_low_hmes = Options.params.filter_out_low_hmes
      # set minimum cut off hme_score or bfr_score to pick fragments with variants
      # calculate min hme score for back or out crossed data or bfr_score for polypoidy data
      # if no filtering applied set cutoff to 1.1
      if filter_out_low_hmes and ratio_type == :hmes
        adjust = Options.params.hmes_adjust
        if Options.params.cross == 'back'
          cutoff = (1.0/adjust) + 1.0
        else # outcross
          cutoff = (2.0/adjust) + 1.0
        end
      elsif filter_out_low_hmes and ratio_type == :bfr
        cutoff = bfr_cutoff(selected_contigs)
      else
        cutoff = 1.1
      end

      selected_contigs.each_key do | frag |
        if ratio_type == :hmes and selected_contigs[frag].hme_score < cutoff
          selected_contigs[frag].delete
        elsif ratio_type == :bfr and selected_contigs[frag].bfr_score < cutoff
          selected_contigs[frag].delete
        end
      end
      selected_contigs
    end

    def bfr_cutoff(selected_contigs, prop=0.1)
      ratios = []
      selected_contigs.each_key do | frag |
        ratios << selected_contigs[frag].bfr_score
      end
      ratios.sort!.reverse!
      index = (ratios.length * prop)/100
      # set a minmum index to get at least one contig
      if index < 1
        index = 1
      end
      ratios[index - 1]
    end

    # method is to discard homozygous variant positions for which background bulk
    # pileup shows proportion higher than 0.35 for variant allele/non-reference allele
    # a recessive variant is expected to have 1/3rd frequency in background bulk
    def verify_bg_bulk_pileup
      self.hmes_frags.each_key do | frag |
        positions = @assembly[frag].hm_pos
        contig_pileup_obj = @pileups[frag]
        positions.each do | pos |
          if contig_pileup_obj.mut_bulk.key?(pos)
            mut_pileup = contig_pileup_obj.mut_bulk[pos]
            if mut_pileup.is_var
              if contig_pileup_obj.bg_bulk.key?(pos)
                bg_pileup = contig_pileup_obj.bg_bulk[pos]
                if bg_pileup.non_ref_ratio > 0.35
                  @assembly[frag].hm_pos.delete(pos)
                end
              end
            else
              # this should not happen, may be catch as as an error
              @assembly[frag].hm_pos.delete(pos)
            end
          else
            # this should not happen, may be catch as as an error
            @assembly[frag].hm_pos.delete(pos)
          end
        end
      end
    end

  end # Variants

end # Cheripic
