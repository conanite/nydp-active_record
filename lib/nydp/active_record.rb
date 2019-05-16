require "nydp/active_record/version"

module Nydp
  module ActiveRecord
    module UsesNydp   ; def uses_nydp? ; true  ; end ; end
    module UsesNoNydp ; def uses_nydp? ; false ; end ; end

    module Callback
      def use_nydp
        after_save   -> { nydp_event :"after-save" }
        after_create -> { nydp_event :"after-create" }
        attr_accessor :nydp_hook_in_progress
        include InstanceMethods, UsesNydp
        extend  UsesNydp
        self.on_use_nydp if respond_to?(:on_use_nydp)
      end

      module InstanceMethods
        def _nydp_run_event_hook e
          self.nydp_hook_in_progress = true
          Site.nydp :"run-event-hooks", e, self
        ensure
          self.nydp_hook_in_progress = false
        end

        def nydp_event e ; _nydp_run_event_hook e unless nydp_hook_in_progress ; end
      end
    end


    class Plugin
      def name            ; "Nydp Rails ActiveRecord Integration" ; end
      def loadfiles       ; []                                    ; end
      def testfiles       ; []                                    ; end
      def setup ns
        Nydp::Symbol.mk("update" , ns).assign(Builtin::Update.instance )
        Nydp::Symbol.mk("create" , ns).assign(Builtin::Create.instance )
        Nydp::Symbol.mk("find"   , ns).assign(Builtin::Find.instance   )
        Nydp::Symbol.mk("build"  , ns).assign(Builtin::Build.instance  )
      end
    end

    module Builtin
      class Persist
        include Singleton, Nydp::Helper, Nydp::Builtin::Base

        def veto_attrs_msg attrs ; "attrs must be a hash, got #{attrs.class.inspect} : #{attrs.inspect}" ; end
        def veto_attrs     attrs ; raise veto_attrs_msg(attrs) unless attrs.is_a?(::Hash)        ; attrs ; end
        def sanitise_attrs attrs ; ::ActiveRecord::Base.nydp_sanitise_attrs attrs                        ; end

        def builtin_invoke vm, args
          klass = ::ActiveRecord::Base.nydp_find_descendant(args.car.to_s)
          attrs = n2r(args.cdr.car)
          raise "unknown entity type : #{args.car.inspect}"            if klass.nil?
          raise "Can't #{action_name} #{klass.name} : not allowed" unless klass.uses_nydp?

          vm.push_arg r2n(doit(klass, sanitise_attrs(veto_attrs attrs)), vm.ns)
        end
      end

      class Create < Persist
        def action_name       ; "create"                  ; end
        def doit klass, attrs ; klass._nydp_create! attrs ; end
      end

      class Find < Persist
        def veto_attrs     id ; raise "expected int, got #{id.inspect}" unless id.is_a?(::String) || id.is_a?(Fixnum) ; id ; end
        def sanitise_attrs id ; id.to_i       ; end
        def action_name       ; "find"        ; end
        def doit    klass, id ; klass.find id ; end
      end

      class Build < Persist
        def action_name       ; "build"         ; end
        def doit klass, attrs ; klass.new attrs ; end
      end

      class Update < Persist # just for #sanitise_attrs
        def unprocessable         e ; raise "Can't update #{e.class.name} : not allowed"              ; end
        def do_update          e, a ; e.tap { |ent| ent.update_attributes sanitise_attrs a }          ; end
        def update_entity      e, a ; e.uses_nydp? ? do_update(e, a) : unprocessable(e)               ; end
        def builtin_invoke vm, args ; vm.push_arg r2n update_entity(n2r(args.car), n2r(args.cdr.car)) ; end
      end

    end

    module Integration
      include Nydp::AutoWrap

      def self.nydp_find_descendant name ; descendants.detect { |kla| kla.name == name } ; end

      # override this to control what gets through 'update, 'build and 'create
      def self.nydp_sanitise_attrs attrs ; attrs                                         ; end

      def _nydp_whitelist       ; []                                                                                   ; end
      def nydp_type             ; @_nydp_type ||= self.class.name.underscore_more                                      ; end
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
    end

    class CollectionProxy < Nydp::Pair
      module Integration
        def _nydp_wrapper ; @_nydp_wrapper ||= (size == 0) ? Nydp::NIL : CollectionProxy.new(self, 0, size) ; end
      end

      def initialize things, idx, size0 ; @collection, @index, @size0 = things, idx, size0     ; end
      def car                           ; @car_proxy ||= @collection[@index]                   ; end
      def cdr                           ; @cdr_proxy ||= rest_of_list                          ; end
      def size                          ; @size0 - @index                                      ; end

      private

      def rest_of_list
        if size <= 1 ; Nydp::NIL
        else         ; self.class.new(@collection, (@index + 1), @size0)
        end
      end
    end
  end
end

::ActiveRecord::Base.send                          :include, ::Nydp::ActiveRecord::Integration
::ActiveRecord::Associations::CollectionProxy.send :include, ::Nydp::ActiveRecord::CollectionProxy::Integration
::ActiveRecord::Relation.send                      :include, ::Nydp::ActiveRecord::CollectionProxy::Integration
::ActiveRecord::Base.send                          :include, ::Nydp::ActiveRecord::UsesNoNydp
::ActiveRecord::Base.send                          :extend , ::Nydp::ActiveRecord::Callback, ::Nydp::ActiveRecord::UsesNoNydp
Nydp.plug_in ::Nydp::ActiveRecord::Plugin.new
