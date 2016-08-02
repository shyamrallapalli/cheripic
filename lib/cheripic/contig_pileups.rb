# encoding: utf-8
require 'bio'
require 'forwardable'

module Cheripic

  # Custom error handling for ContigPileup class
  class ContigPileupsError < CheripicError; end

  # A ContigPileup object for each contig from assembly that stores
  # pileup file information and variants are selected from analysis of pileup files
  # selected variants from pileup files is stored as hashes
  #
  # @!attribute [rw] id
  #   @return [String] id of the contig in assembly taken from fasta file
  # @!attribute [rw] mut_bulk
  #   @return [Hash] a hash of variant positions from mut_bulk as keys and pileup info as values
  # @!attribute [rw] bg_bulk
  #   @return [Hash] a hash of variant positions from bg_bulk as keys and pileup info as values
  # @!attribute [rw] mut_parent
  #   @return [Hash] a hash of variant positions from mut_parent as keys and pileup info as values
  # @!attribute [rw] bg_parent
  #   @return [Hash] a hash of variant positions from bg_parent as keys and pileup info as values
  # @!attribute [rw] parent_hemi
  #   @return [Hash] a hash of hemi-variant positions as keys and bfr calculated from parent bulks as values
  class ContigPileups

    include Enumerable
    extend Forwardable
    def_delegators :@mut_bulk, :each, :each_key, :each_value, :length, :[], :store
    def_delegators :@bg_bulk, :each, :each_key, :each_value, :length, :[], :store
    def_delegators :@mut_parent, :each, :each_key, :each_value, :length, :[], :store
    def_delegators :@bg_parent, :each, :each_key, :each_value, :length, :[], :store
    attr_accessor :id, :parent_hemi
    attr_accessor :mut_bulk, :bg_bulk, :mut_parent, :bg_parent

    def initialize (fasta)
      @id = fasta
      @mut_bulk = {}
      @bg_bulk = {}
      @mut_parent = {}
      @bg_parent = {}
      @parent_hemi = {}
    end

    def bulks_compared
      @hm_pos = {}
      @ht_pos = {}
      @hemi_pos = {}
      @mut_bulk.each_key do | pos |
        if Options.polyploidy and @parent_hemi.key?(pos)
          bg_bases = ''
          if @bg_bulk.key?(pos)
            bg_bases = @bg_bulk[pos].var_base_frac
          end
          mut_bases = @mut_bulk[pos].var_base_frac
          bfr = Bfr.get_bfr(mut_bases, bg_bases)
          @hemi_pos[pos] = bfr
        else
          self.compare_pileup(pos)
        end
      end
      [@hm_pos, @ht_pos, @hemi_pos]
    end

    # we are only dealing with single element hashes
    # so discard hashes with more than one element and empty hashes
    # empty hash results from position below selected coverage or bases freq below noise
    def compare_pileup(pos)
      base_hash = @mut_bulk[pos].var_base_frac
      base_hash.delete(:ref)
      return nil if base_hash.empty?
      # we could ignore complex loci or
      # take the variant type based on predominant base
      if base_hash.length > 1
        mut_type, ratio = var_mode(base_hash.values.max)
      else
        base = base_hash.keys[0]
        mut_type, ratio = var_mode(base_hash[base])
      end
      if @bg_bulk.key?(pos)
        bg_type = bg_bulk_var(pos)
        mut_type = compare_var_type(mut_type, bg_type)
      end
      unless mut_type == nil
        categorise_pos(mut_type, pos, ratio)
      end
    end

    # if both bulks have homozygous var at this position
    # then ignore the position
    def compare_var_type(muttype, bgtype)
      if muttype == :hom and bgtype == :hom
        nil
      else
        muttype
      end
    end

    def bg_bulk_var(pos)
      bg_base_hash = @bg_bulk[pos].var_base_frac
      if bg_base_hash.length > 1
        # taking only var mode
        var_mode(bg_base_hash.values.max)[0]
      else
        # taking only var mode
        var_mode(bg_base_hash[0])[0]
      end
    end

    def categorise_pos(var_type, pos, ratio)
      if var_type == :hom
        @hm_pos[pos] = ratio
      elsif var_type == :het
        @ht_pos[pos] = ratio
      end
    end

    # calculate var zygosity for non-polyploid variants
    # increased range is used for heterozygosity for RNA-seq data
    def var_mode(ratio)
      ht_low = Options.htlow
      ht_high = Options.hthigh
      mode = ''
      if ratio.between?(ht_low, ht_high)
        mode = :het
      elsif ratio > ht_high
        mode = :hom
      end
      [mode, ratio]
    end

    def hemisnps_in_parent
      # mark all the hemi snp based on both parents
      self.mut_parent.each_key do |pos|
        mut_parent_frac = @mut_parent[pos].var_base_frac
        if self.bg_parent.key?(pos)
          bg_parent_frac = @bg_parent[pos].var_base_frac
          bfr = Bfr.get_bfr(mut_parent_frac, bg_parent_frac)
          @parent_hemi[pos] = bfr
          self.bg_parent.delete(pos)
        else
          bfr = Bfr.get_bfr(mut_parent_frac)
          @parent_hemi[pos] = bfr
        end
      end

      # now include all hemi snp unique to background parent
      self.bg_parent.each_key do |pos|
        unless @parent_hemi.key?(pos)
          bg_parent_frac = @bg_parent[pos].var_base_frac
          bfr = Bfr.get_bfr(bg_parent_frac)
          @parent_hemi[pos] = bfr
        end
      end
    end

  end

end
