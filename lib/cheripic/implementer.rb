#!/usr/bin/env ruby

module Cheripic

  class ImplementerError < CheripicError; end

  class Implementer

    require 'ostruct'
    require 'fileutils'
    attr_accessor :options, :variants

    def initialize(inputs)
      set1 = %i{assembly
                input_format
                mut_bulk
                bg_bulk
                output
                mut_parent
                bg_parent}
      @options = OpenStruct.new(inputs.select { |k| set1.include?(k) })

      set2 = %i{hmes_adjust
                htlow
                hthigh
                mindepth
                min_non_ref_count
                min_indel_count_support
                ignore_reference_n
                mapping_quality
                base_quality
                noise
                cross_type
                only_frag_with_vars
                filter_out_low_hmes
                polyploidy
                bfr_adjust}
      settings = inputs.select { |k| set2.include?(k) }
      Options.update(settings)
      FileUtils.mkdir_p @options.output
    end

    def extract_vars
      @variants = Variants.new(@options)
      @variants.compare_pileups
    end

    def process_variants
      @variants.verify_bg_bulk_pileup
      # print selected variants that could be potential markers or mutation

    end

    def run
      unless defined?(@variants.has_run)
        self.extract_vars
      end
      if Options.params.polyploidy
        self.process_variants
        @variants.bfr_frags
      else
        self.process_variants
      end
    end

  end

end
