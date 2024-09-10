require 'singleton'
require "nydp"
require "nydp/active_record/version"
require "nydp/plugin"

module Nydp
  module ActiveRecord
    module UsesNydp   ; def uses_nydp? ; true  ; end ; end
    module UsesNoNydp ; def uses_nydp? ; false ; end ; end

    module Callback
      def use_nydp
        after_save   -> { nydp_event :"after-save"   }
        after_create -> { nydp_event :"after-create" }
        after_commit -> { nydp_event :"after-create-commit" }, on: :create
        after_touch  -> { nydp_event :"after-touch"  }
        attr_accessor :nydp_hook_in_progress
        include InstanceMethods, UsesNydp
        extend  UsesNydp
        self.on_use_nydp if respond_to?(:on_use_nydp)
      end

      module InstanceMethods
        def _nydp_run_event_hook e
          return if Thread.current[:disable_nydp_active_record_event_hooks]
          self.nydp_hook_in_progress = true
          nydp_call :"run-event-hooks", e, self
        ensure
          self.nydp_hook_in_progress = false
        end

        def nydp_event e ; _nydp_run_event_hook e unless nydp_hook_in_progress ; end
      end
    end

    class Plugin
      include Nydp::PluginHelper
      def base_path          ; relative_path "../lisp/"                                              ; end
      def name               ; "Nydp Rails ActiveRecord Integration"                                 ; end
      def loadfiles          ; file_readers Dir.glob(relative_path '../lisp/*.nydp').sort ; end
      def testfiles          ; []                                                                    ; end
      def setup ns
        ns.assign(:"update"        , Builtin::Update.instance           )
        ns.assign(:"assign-attrs"  , Builtin::AssignAttributes.instance )
        ns.assign(:"create"        , Builtin::Create.instance           )
        ns.assign(:"destroy"       , Builtin::Destroy.instance          )
        ns.assign(:"find"          , Builtin::Find.instance             )
        ns.assign(:"all-instances" , Builtin::AllInstances.instance     )
        ns.assign(:"build"         , Builtin::Build.instance            )
        ns.assign(:"find-or-create", Builtin::FindCreate.instance       )
        ns.assign(:"save"          , Builtin::Save.instance             )
      end
    end

    module Builtin
      class Persist
        include Singleton, Nydp::Helper, Nydp::Builtin::Base

        # def veto_attrs_msg attrs ; "attrs must be a hash, got #{attrs.class.inspect} : #{attrs.inspect}" ; end
        # def veto_attrs     attrs ; raise veto_attrs_msg(attrs) unless attrs.is_a?(::Hash)        ; attrs ; end
        def veto_attrs     kla, attrs ; attrs                         ; end
        def sanitise_attrs kla, attrs ; kla.nydp_sanitise_attrs attrs ; end

        def builtin_call *args
          klass = ::ActiveRecord::Base.nydp_find_descendant(args.first.to_s)
          attrs = rubify(args[1])
          raise "unknown entity type : #{args.first.inspect}"          if klass.nil?
          raise "Can't #{action_name} #{klass.name} : not allowed" unless klass.uses_nydp?


          r2n(doit(klass, sanitise_attrs(klass, veto_attrs(klass, attrs))))
        end
      end

      class Create < Persist
        def action_name       ; "create"                  ; end
        def doit klass, attrs ; klass._nydp_create! attrs ; end
      end

      class Find < Persist
        def error_not_found kla, id ; raise ::ActiveRecord::RecordNotFound.new "can't find #{kla.name} with id #{id.inspect}, expected id to be an integer" ; end
        def id_ok                id ; id.is_a?(::String) || id.is_a?(Integer)           ; end
        def veto_attrs      kla, id ; error_not_found(kla, id) unless id_ok(id)    ; id ; end
        def sanitise_attrs  kla, id ; id.to_i                                           ; end
        def action_name             ; "find"                                            ; end
        def doit            kla, id ; kla.find id                                       ; end
      end

      class AllInstances < Persist
        def veto_attrs     k,a ; a               ; end
        def sanitise_attrs k,a ; a               ; end
        def action_name        ; "all-instances" ; end
        def doit      klass, _ ; klass.all       ; end
      end

      class FindCreate < Persist
        def action_name       ; "find_or_create"                ; end
        def doit klass, attrs ; klass._nydp_find_or_create_by!(attrs) ; end
      end

      class Build < Persist
        def action_name       ; "build"         ; end
        def doit klass, attrs ; klass.new attrs ; end
      end

      class Update < Persist # just for #sanitise_attrs
        def unprocessable    e ; raise "Can't update #{e.class.name} : not allowed"    ; end
        def do_update     e, a ; e.tap { |ent| ent.update sanitise_attrs(e.class, a) } ; end
        def update_entity e, a ; e.uses_nydp? ? do_update(e, a) : unprocessable(e)     ; end
        def builtin_call *args ; r2n update_entity(n2r(args[0]), rubify(args[1]))      ; end
      end

      class AssignAttributes < Update # just for #sanitise_attrs
        def assignable e, a ; sanitise_attrs(e.class, a).slice *e.attributes.keys.map(&:to_sym) ; end
        def do_update  e, a ; e.tap { |ent| ent.assign_attributes assignable(e, a) }            ; end
      end

      class Destroy < Persist # just for #sanitise_attrs
        def unprocessable    e ; raise "Can't destroy #{e.class.name} : not allowed" ; end
        def destroy_entity   e ; e.uses_nydp? ? e.destroy : unprocessable(e)         ; end
        def builtin_call *args ; r2n destroy_entity(n2r(args[0]))                    ; end
      end

      class Save < Persist
        def builtin_call e ; e.uses_nydp? ? e.save! : unprocessable(e) ; end
      end
    end

    module Integration
      include Nydp::AutoWrap

      def nydp_type             ; @_nydp_type ||= self.class.name.underscore.gsub("/", "_")                            ; end
      def nydp_inspect_exclude  ; %w{ site_id id search_text created_at updated_at password salt }                     ; end
      def nydp_noinspect?  k, v ; self.class.column_defaults[k] == v || self.class.column_defaults[k].nil? && v == ""  ; end
      def nydp_inspectable      ; attributes.except(*nydp_inspect_exclude).delete_if { |k, v| nydp_noinspect? k, v }   ; end
      def nydp_inspect_attr   a ; a.is_a?(String) ? a.truncate(64).inspect : (a.is_a?(BigDecimal) ? a.to_f : a._nydp_wrapper.inspect) ; end
      def nydp_inspect_attrs    ; nydp_inspectable.map { |k,v| "#{k} #{nydp_inspect_attr v}" }                                        ; end
      def inspect               ; "(#{self.class.name}##{id} { #{nydp_inspect_attrs.join(" ")} })"                                    ; end
      def _nydp_get method_name
        key_name = method_name.to_s.gsub(/-/, '_')
        nydp_method = :"_nydp_get_#{key_name}"
        key = key_name.to_sym

        if    respond_to?(nydp_method)                           ; send nydp_method
        elsif attributes.key? key_name                           ; send key
        elsif respond_to?(:tag_types) && tag_types.include?(key) ; send(:"#{key.to_s.singularize}_list")
        elsif self.class.reflections.key? key.to_s               ; send key
        elsif attributes.key? "#{key_name}_file_name"            ; send key
        elsif key == :unwrap                                     ; self
        else                                                     ; _nydp_safe_send key
        end._nydp_wrapper
      end

      def self.included base
        def base.nydp_find_descendant name ; descendants.detect { |kla| kla.name == name } ; end

        # override this to control what gets through 'update, 'build and 'create
        def base.nydp_sanitise_attrs attrs ; attrs                         ; end

        # override these to control creation behaviour in your models
        def base._nydp_create!            attrs ; create! attrs            ; end
        def base._nydp_find_or_create_by! attrs ; find_or_create_by! attrs ; end

        base.class_attribute :_nydp_whitelist
        base.class_attribute :_nydp_procs
        base._nydp_whitelist = Set.new
        base._nydp_procs     = Set.new
        delegate :_nydp_whitelist, to: :"self.class"
        delegate :_nydp_procs    , to: :"self.class"
      end
    end

    class CollectionProxy < Nydp::Pair
      module Integration
        def _nydp_wrapper ;
          return @_nydp_wrapper if @_nydp_wrapper && @_nydp_wrapper.to_ruby.object_id == self.object_id
          @_nydp_wrapper = (size == 0) ? Nydp::NIL : CollectionProxy.new(self, 0, size) ; end
      end

      def initialize things, idx, size0 ; @collection, @index, @size0 = things, idx, size0     ; end
      def car                     ; @car_proxy ||= @collection[@index] ; end
      def cdr                     ; @cdr_proxy ||= rest_of_list        ; end
      def size                    ; @size0 - @index                    ; end
      def collection              ; @collection                        ; end
      def _nydp_get method_name
        case method_name.to_s.gsub(/-/, '_').to_sym
        when :offset        ; @collection.offset
        when :per_page      ; @collection.per_page
        when :total_entries ; @collection.total_entries
        when :total_pages   ; @collection.total_pages
        else nil
        end._nydp_wrapper
      end

      private

      def rest_of_list
        if size <= 1 ; Nydp::NIL
        else         ; self.class.new(@collection, (@index + 1), @size0)
        end
      end
    end
  end
end

if defined? ::ActiveRecord
  ::ActiveRecord::Base.send                          :include, ::Nydp::ActiveRecord::Integration
  ::ActiveRecord::Associations::CollectionProxy.send :include, ::Nydp::ActiveRecord::CollectionProxy::Integration
  ::ActiveRecord::Relation.send                      :include, ::Nydp::ActiveRecord::CollectionProxy::Integration
  ::ActiveRecord::Base.send                          :include, ::Nydp::ActiveRecord::UsesNoNydp
  ::ActiveRecord::Base.send                          :extend , ::Nydp::ActiveRecord::Callback, ::Nydp::ActiveRecord::UsesNoNydp
end
Nydp.plug_in ::Nydp::ActiveRecord::Plugin.new
