# frozen_string_literal: true

module Decidim
  module ContractsSk
    # The engine's one case-insensitive substring match, shared by the public
    # catalogue (q and party) and the admin index (q) so the three can never
    # drift apart again (civora-org/civora-platform#116).
    #
    # Two defects of the earlier per-controller condition are fixed here:
    #
    # * the column was lower-cased in SQL but the pattern was not, so on
    #   PostgreSQL (where LIKE is case-sensitive) an upper-case term never
    #   matched; the term is now down-cased in Ruby, the column in SQL;
    # * sanitize_sql_like escapes % and _ with a backslash, but a LIKE has no
    #   default escape character on SQLite (nor is it guaranteed elsewhere),
    #   so the backslash matched literally and the wildcards stayed live;
    #   every condition now carries an explicit ESCAPE clause.
    #
    # Known limit: SQLite's LOWER() folds ASCII only, so a diacritic in the
    # stored column ("Š") is not folded there; PostgreSQL folds per the
    # database collation. Production runs PostgreSQL.
    module TextSearch
      ESCAPE = "\\"

      # Control characters (a NUL byte makes PostgreSQL raise on bind) become
      # spaces, so a term with a tab or newline still splits words sanely.
      # Callers strip/squish afterwards.
      def self.clean(term)
        term.to_s.gsub(/[[:cntrl:]]/, " ")
      end

      # One "LOWER(col) LIKE :pattern ESCAPE '\'" clause per column, OR-ed.
      def self.condition(*columns)
        columns.map { |column| "LOWER(#{column}) LIKE :pattern ESCAPE '#{ESCAPE}'" }.join(" OR ")
      end

      # The LIKE pattern for a term: down-cased, wildcards escaped, wrapped
      # for a substring match. Pair with .condition (named bind :pattern).
      def self.pattern(term)
        "%#{ActiveRecord::Base.sanitize_sql_like(term.to_s.downcase, ESCAPE)}%"
      end

      # The catalogue / admin free-text fields.
      # Columns are table-qualified, so the condition stays unambiguous when a
      # reusing scope joins another table.
      CONTRACT_CONDITION = condition(*%w[title reference].map { |c| "#{Contract.table_name}.#{c}" }).freeze
      # The party name match carries its IČO guard in the SQL itself: a name
      # is searched only among parties that have an IČO (a party without one
      # may be a natural person: never profiled, DPIA #135).
      PARTY_CONDITION =
        "(#{condition("#{Party.table_name}.name")}) " \
        "AND #{Party.table_name}.ico IS NOT NULL AND #{Party.table_name}.ico <> ''".freeze
    end
  end
end
