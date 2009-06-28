/* valacodewriter.vala
 *
 * Copyright (C) 2006-2009  Jürg Billeter
 * Copyright (C) 2006-2008  Raffaele Sandrini
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Jürg Billeter <j@bitron.ch>
 *	Raffaele Sandrini <raffaele@sandrini.ch>
 */

using Gee;

/**
 * Code visitor generating Vala API file for the public interface.
 */
public class Vala.CodeWriter : CodeVisitor {
	private CodeContext context;
	
	FileStream stream;
	
	int indent;
	/* at begin of line */
	bool bol = true;

	Scope current_scope;

	bool dump_tree;
	bool emit_internal;

	string? override_header = null;
	string? header_to_override = null;

	public CodeWriter (bool dump_tree = false, bool emit_internal = false) {
		this.dump_tree = dump_tree;
		this.emit_internal = emit_internal;
	}

	/**
	 * Allows overriding of a specific cheader in the output
	 * @param original orignal cheader to override
	 * @param replacement cheader to replace original with
	 */
	public void set_cheader_override (string original, string replacement)
	{
		header_to_override = original;
		override_header = replacement;
	}

	/**
	 * Writes the public interface of the specified code context into the
	 * specified file.
	 *
	 * @param context  a code context
	 * @param filename a relative or absolute filename
	 */
	public void write_file (CodeContext context, string filename) {
		this.context = context;
	
		stream = FileStream.open (filename, "w");

		write_string ("/* %s generated by %s, do not modify. */".printf (Path.get_basename (filename), Environment.get_prgname ()));
		write_newline ();
		write_newline ();

		current_scope = context.root.scope;

		context.accept (this);

		current_scope = null;

		stream = null;
	}

	public override void visit_namespace (Namespace ns) {
		if (ns.external_package) {
			return;
		}

		if (ns.name == null)  {
			ns.accept_children (this);
			return;
		}

		write_indent ();
		write_string ("[CCode (cprefix = \"%s\", lower_case_cprefix = \"%s\")]".printf (ns.get_cprefix (), ns.get_lower_case_cprefix ()));
		write_newline ();

		write_attributes (ns);

		write_indent ();
		write_string ("namespace ");
		write_identifier (ns.name);
		write_begin_block ();

		current_scope = ns.scope;

		visit_sorted (ns.get_namespaces ());
		visit_sorted (ns.get_classes ());
		visit_sorted (ns.get_interfaces ());
		visit_sorted (ns.get_structs ());
		visit_sorted (ns.get_enums ());
		visit_sorted (ns.get_error_domains ());
		visit_sorted (ns.get_delegates ());
		visit_sorted (ns.get_fields ());
		visit_sorted (ns.get_constants ());
		visit_sorted (ns.get_methods ());

		current_scope = current_scope.parent_scope;

		write_end_block ();
		write_newline ();
	}

	private string get_cheaders (Symbol cl) {
		bool first = true;
		string cheaders = "";
		foreach (string cheader in cl.get_cheader_filenames ()) {
			if (header_to_override != null &&
			    cheader == header_to_override) {
				cheader = override_header;
			}
			if (first) {
				cheaders = cheader;
				first = false;
			} else {
				cheaders = "%s,%s".printf (cheaders, cheader);
			}
		}
		return cheaders;
	}

	public override void visit_class (Class cl) {
		if (cl.external_package) {
			return;
		}

		if (!check_accessibility (cl)) {
			return;
		}

		if (cl.is_compact) {
			write_indent ();
			write_string ("[Compact]");
			write_newline ();
		}

		if (cl.is_immutable) {
			write_indent ();
			write_string ("[Immutable]");
			write_newline ();
		}

		write_indent ();
		
		write_string ("[CCode (");

		if (cl.is_reference_counting ()) {
			if (cl.base_class == null || cl.base_class.get_ref_function () == null || cl.base_class.get_ref_function () != cl.get_ref_function ()) {
				write_string ("ref_function = \"%s\", ".printf (cl.get_ref_function ()));
				if (cl.ref_function_void) {
					write_string ("ref_function_void = true, ");
				}
			}
			if (cl.base_class == null || cl.base_class.get_unref_function () == null || cl.base_class.get_unref_function () != cl.get_unref_function ()) {
				write_string ("unref_function = \"%s\", ".printf (cl.get_unref_function ()));
			}
		} else {
			if (cl.get_dup_function () != null) {
				write_string ("copy_function = \"%s\", ".printf (cl.get_dup_function ()));
			}
			if (cl.get_free_function () != cl.get_default_free_function ()) {
				write_string ("free_function = \"%s\", ".printf (cl.get_free_function ()));
			}
		}

		if (cl.get_cname () != cl.get_default_cname ()) {
			write_string ("cname = \"%s\", ".printf (cl.get_cname ()));
		}

		if (cl.type_check_function != null) {
			write_string ("type_check_function = \"%s\", ".printf (cl.type_check_function ));
		}

		if (cl.is_compact && cl.get_type_id () != "G_TYPE_POINTER") {
			write_string ("type_id = \"%s\", ".printf (cl.get_type_id ()));
		}

		if (cl.get_param_spec_function () != null
		    && (cl.base_class == null || cl.get_param_spec_function () != cl.base_class.get_param_spec_function ())) {
			write_string ("param_spec_function = \"%s\", ".printf (cl.get_param_spec_function ()));
		}

		write_string ("cheader_filename = \"%s\")]".printf (get_cheaders(cl)));
		write_newline ();

		write_attributes (cl);
		
		write_indent ();
		write_accessibility (cl);
		if (cl.is_abstract) {
			write_string ("abstract ");
		}
		write_string ("class ");
		write_identifier (cl.name);

		var type_params = cl.get_type_parameters ();
		if (type_params.size > 0) {
			write_string ("<");
			bool first = true;
			foreach (TypeParameter type_param in type_params) {
				if (first) {
					first = false;
				} else {
					write_string (",");
				}
				write_identifier (type_param.name);
			}
			write_string (">");
		}

		var base_types = cl.get_base_types ();
		if (base_types.size > 0) {
			write_string (" : ");
		
			bool first = true;
			foreach (DataType base_type in base_types) {
				if (!first) {
					write_string (", ");
				} else {
					first = false;
				}
				write_type (base_type);
			}
		}
		write_begin_block ();

		current_scope = cl.scope;

		visit_sorted (cl.get_classes ());
		visit_sorted (cl.get_structs ());
		visit_sorted (cl.get_enums ());
		visit_sorted (cl.get_delegates ());
		visit_sorted (cl.get_fields ());
		visit_sorted (cl.get_constants ());
		visit_sorted (cl.get_methods ());
		visit_sorted (cl.get_properties ());
		visit_sorted (cl.get_signals ());

		current_scope = current_scope.parent_scope;

		write_end_block ();
		write_newline ();
	}

	void visit_sorted (Gee.List<Symbol> symbols) {
		var sorted_symbols = new Gee.ArrayList<Symbol> ();
		foreach (Symbol sym in symbols) {
			int left = 0;
			int right = sorted_symbols.size - 1;
			if (left > right || sym.name < sorted_symbols[left].name) {
				sorted_symbols.insert (0, sym);
			} else if (sym.name > sorted_symbols[right].name) {
				sorted_symbols.add (sym);
			} else {
				while (right - left > 1) {
					int i = (right + left) / 2;
					if (sym.name > sorted_symbols[i].name) {
						left = i;
					} else {
						right = i;
					}
				}
				sorted_symbols.insert (left + 1, sym);
			}
		}
		foreach (Symbol sym in sorted_symbols) {
			sym.accept (this);
		}
	}

	public override void visit_struct (Struct st) {
		if (st.external_package) {
			return;
		}

		if (!check_accessibility (st)) {
			return;
		}
		
		write_indent ();

		write_string ("[CCode (");

		if (st.get_cname () != st.get_default_cname ()) {
			write_string ("cname = \"%s\", ".printf (st.get_cname ()));
		}

		if (!st.is_simple_type () && st.get_type_id () != "G_TYPE_POINTER") {
			write_string ("type_id = \"%s\", ".printf (st.get_type_id ()));
		}

                if (!st.use_const) {
                        write_string ("use_const = false, ");
                }

		write_string ("cheader_filename = \"%s\")]".printf (get_cheaders(st)));
		write_newline ();

		if (st.is_simple_type ()) {
			write_indent ();
			write_string ("[SimpleType]");
			write_newline ();
		}

		if (st.is_integer_type ()) {
			write_indent ();
			write_string ("[IntegerType (rank = %d)]".printf (st.get_rank ()));
			write_newline ();
		}

		if (st.is_floating_type ()) {
			write_indent ();
			write_string ("[FloatingType (rank = %d)]".printf (st.get_rank ()));
			write_newline ();
		}

		write_attributes (st);

		write_indent ();
		write_accessibility (st);
		write_string ("struct ");
		write_identifier (st.name);

		if (st.base_type != null) {
			write_string (" : ");
			write_type (st.base_type);
		}

		write_begin_block ();

		current_scope = st.scope;

		foreach (Field field in st.get_fields ()) {
			field.accept (this);
		}
		visit_sorted (st.get_constants ());
		visit_sorted (st.get_methods ());

		current_scope = current_scope.parent_scope;

		write_end_block ();
		write_newline ();
	}

	public override void visit_interface (Interface iface) {
		if (iface.external_package) {
			return;
		}

		if (!check_accessibility (iface)) {
			return;
		}

		write_indent ();

		write_string ("[CCode (cheader_filename = \"%s\"".printf (get_cheaders(iface)));
		if (iface.get_lower_case_csuffix () != iface.get_default_lower_case_csuffix ())
			write_string (", lower_case_csuffix = \"%s\"".printf (iface.get_lower_case_csuffix ()));

		write_string (")]");
		write_newline ();

		write_attributes (iface);

		write_indent ();
		write_accessibility (iface);
		write_string ("interface ");
		write_identifier (iface.name);

		var type_params = iface.get_type_parameters ();
		if (type_params.size > 0) {
			write_string ("<");
			bool first = true;
			foreach (TypeParameter type_param in type_params) {
				if (first) {
					first = false;
				} else {
					write_string (",");
				}
				write_identifier (type_param.name);
			}
			write_string (">");
		}

		var prerequisites = iface.get_prerequisites ();
		if (prerequisites.size > 0) {
			write_string (" : ");
		
			bool first = true;
			foreach (DataType prerequisite in prerequisites) {
				if (!first) {
					write_string (", ");
				} else {
					first = false;
				}
				write_type (prerequisite);
			}
		}
		write_begin_block ();

		current_scope = iface.scope;

		visit_sorted (iface.get_classes ());
		visit_sorted (iface.get_structs ());
		visit_sorted (iface.get_enums ());
		visit_sorted (iface.get_delegates ());
		visit_sorted (iface.get_fields ());
		visit_sorted (iface.get_methods ());
		visit_sorted (iface.get_properties ());
		visit_sorted (iface.get_signals ());

		current_scope = current_scope.parent_scope;

		write_end_block ();
		write_newline ();
	}

	public override void visit_enum (Enum en) {
		if (en.external_package) {
			return;
		}

		if (!check_accessibility (en)) {
			return;
		}

		write_indent ();

		write_string ("[CCode (cprefix = \"%s\", ".printf (en.get_cprefix ()));

		if (!en.has_type_id) {
			write_string ("has_type_id = \"%d\", ".printf (en.has_type_id ? 1 : 0));
		}

		write_string ("cheader_filename = \"%s\")]".printf (get_cheaders(en)));

		if (en.is_flags) {
			write_indent ();
			write_string ("[Flags]");
		}

		write_attributes (en);

		write_indent ();
		write_accessibility (en);
		write_string ("enum ");
		write_identifier (en.name);
		write_begin_block ();

		bool first = true;
		foreach (EnumValue ev in en.get_values ()) {
			if (first) {
				first = false;
			} else {
				write_string (",");
				write_newline ();
			}

			if (ev.get_cname () != ev.get_default_cname ()) {
				write_indent ();
				write_string ("[CCode (cname = \"%s\")]".printf (ev.get_cname ()));
			}
			write_indent ();
			write_identifier (ev.name);
		}

		if (!first) {
			if (en.get_methods ().size > 0) {
				write_string (";");
			}
			write_newline ();
		}

		current_scope = en.scope;
		foreach (Method m in en.get_methods ()) {
			m.accept (this);
		}
		current_scope = current_scope.parent_scope;

		write_end_block ();
		write_newline ();
	}

	public override void visit_error_domain (ErrorDomain edomain) {
		if (edomain.external_package) {
			return;
		}

		if (!check_accessibility (edomain)) {
			return;
		}

		write_indent ();

		write_string ("[CCode (cprefix = \"%s\", cheader_filename = \"%s\")]".printf (edomain.get_cprefix (), get_cheaders(edomain)));

		write_attributes (edomain);

		write_indent ();
		write_accessibility (edomain);
		write_string ("errordomain ");
		write_identifier (edomain.name);
		write_begin_block ();

		edomain.accept_children (this);

		write_end_block ();
		write_newline ();
	}

	public override void visit_error_code (ErrorCode ecode) {
		write_indent ();
		write_identifier (ecode.name);
		write_string (",");
		write_newline ();
	}

	public override void visit_constant (Constant c) {
		if (c.external_package) {
			return;
		}

		if (!check_accessibility (c)) {
			return;
		}

		bool custom_cname = (c.get_cname () != c.get_default_cname ());
		bool custom_cheaders = (c.parent_symbol is Namespace);
		if (custom_cname || custom_cheaders) {
			write_indent ();
			write_string ("[CCode (");

			if (custom_cname) {
				write_string ("cname = \"%s\"".printf (c.get_cname ()));
			}

			if (custom_cheaders) {
				if (custom_cname) {
					write_string (", ");
				}

				write_string ("cheader_filename = \"%s\"".printf (get_cheaders(c)));
			}

			write_string (")]");
		}

		write_indent ();
		write_accessibility (c);
		write_string ("const ");

		write_type (c.type_reference);
			
		write_string (" ");
		write_identifier (c.name);
		write_string (";");
		write_newline ();
	}

	public override void visit_field (Field f) {
		if (f.external_package) {
			return;
		}

		if (!check_accessibility (f)) {
			return;
		}

		bool custom_cname = (f.get_cname () != f.get_default_cname ());
		bool custom_ctype = (f.get_ctype () != null);
		bool custom_cheaders = (f.parent_symbol is Namespace);
		if (custom_cname || custom_ctype || custom_cheaders || (f.no_array_length && f.field_type is ArrayType)) {
			write_indent ();
			write_string ("[CCode (");

			if (custom_cname) {
				write_string ("cname = \"%s\"".printf (f.get_cname ()));
			}

			if (custom_ctype) {
				if (custom_cname) {
					write_string (", ");
				}

				write_string ("type = \"%s\"".printf (f.get_ctype ()));
			}

			if (custom_cheaders) {
				if (custom_cname || custom_ctype) {
					write_string (", ");
				}

				write_string ("cheader_filename = \"%s\"".printf (get_cheaders(f)));
			}

			if (f.no_array_length && f.field_type is ArrayType) {
				if (custom_cname || custom_ctype || custom_cheaders) {
					write_string (", ");
				}

				write_string ("array_length = false");
			}

			write_string (")]");
		}

		write_indent ();
		write_accessibility (f);

		if (f.binding == MemberBinding.STATIC) {
			write_string ("static ");
		} else if (f.binding == MemberBinding.CLASS) {
			write_string ("class ");
		}

		if (is_weak (f.field_type)) {
			write_string ("weak ");
		}

		write_type (f.field_type);
			
		write_string (" ");
		write_identifier (f.name);
		write_string (";");
		write_newline ();
	}
	
	private void write_error_domains (Gee.List<DataType> error_domains) {
		if (error_domains.size > 0) {
			write_string (" throws ");

			bool first = true;
			foreach (DataType type in error_domains) {
				if (!first) {
					write_string (", ");
				} else {
					first = false;
				}

				write_type (type);
			}
		}
	}

	// equality comparison with 3 digit precision
	private bool float_equal (double d1, double d2) {
		return ((int) (d1 * 1000)) == ((int) (d2 * 1000));
	}

	private void write_params (Gee.List<FormalParameter> params) {
		write_string ("(");

		int i = 1;
		foreach (FormalParameter param in params) {
			if (i > 1) {
				write_string (", ");
			}
			
			if (param.ellipsis) {
				write_string ("...");
				continue;
			}
			

			var ccode_params = new StringBuilder ();
			var separator = "";

			if (param.ctype != null) {
				ccode_params.append_printf ("%stype = \"%s\"", separator, param.ctype);
				separator = ", ";
			}
			if (param.no_array_length && param.parameter_type is ArrayType) {
				ccode_params.append_printf ("%sarray_length = false", separator);
				separator = ", ";
			}
			if (!float_equal (param.carray_length_parameter_position, i + 0.1)) {
				ccode_params.append_printf ("%sarray_length_pos = %g", separator, param.carray_length_parameter_position);
				separator = ", ";
			}
			if (!float_equal (param.cdelegate_target_parameter_position, i + 0.1)) {
				ccode_params.append_printf ("%sdelegate_target_pos = %g", separator, param.cdelegate_target_parameter_position);
				separator = ", ";
			}
			if (param.async_only) {
				ccode_params.append_printf ("%sasync_only = true", separator);
				separator = ", ";
			}

			if (ccode_params.len > 0) {
				write_string ("[CCode (%s)] ".printf (ccode_params.str));
			}

			if (param.params_array) {
				write_string ("params ");
			}

			if (param.direction == ParameterDirection.IN) {
				if (param.parameter_type.value_owned) {
					write_string ("owned ");
				}
			} else {
				if (param.direction == ParameterDirection.REF) {
					write_string ("ref ");
				} else if (param.direction == ParameterDirection.OUT) {
					write_string ("out ");
				}
				if (is_weak (param.parameter_type)) {
					write_string ("unowned ");
				}
			}

			write_type (param.parameter_type);

			write_string (" ");
			write_identifier (param.name);
			
			if (param.default_expression != null) {
				write_string (" = ");
				write_string (param.default_expression.to_string ());
			}

			i++;
		}

		write_string (")");
	}

	public override void visit_delegate (Delegate cb) {
		if (cb.external_package) {
			return;
		}

		if (!check_accessibility (cb)) {
			return;
		}

		write_indent ();

		write_string ("[CCode (cheader_filename = \"%s\"".printf (get_cheaders(cb)));

		if (!cb.has_target) {
			write_string (", has_target = false");
		}

		write_string (")]");

		write_indent ();

		write_accessibility (cb);
		write_string ("delegate ");
		
		write_return_type (cb.return_type);
		
		write_string (" ");
		write_identifier (cb.name);
		
		write_string (" ");
		
		write_params (cb.get_parameters ());

		write_string (";");

		write_newline ();
	}

	public override void visit_method (Method m) {
		if (m.external_package) {
			return;
		}

		// don't write interface implementation unless it's an abstract or virtual method
		if (!check_accessibility (m) || (m.base_interface_method != null && !m.is_abstract && !m.is_virtual)) {
			if (!dump_tree) {
				return;
			}
		}

		if (m.get_attribute ("NoWrapper") != null) {
			write_indent ();
			write_string ("[NoWrapper]");
		}
		if (m.returns_modified_pointer) {
			write_indent ();
			write_string ("[ReturnsModifiedPointer]");
		}
		if (m.printf_format) {
			write_indent ();
			write_string ("[PrintfFormat]");
		}

		var ccode_params = new StringBuilder ();
		var separator = "";

		if (m.get_cname () != m.get_default_cname ()) {
			ccode_params.append_printf ("%scname = \"%s\"", separator, m.get_cname ());
			separator = ", ";
		}
		if (m.parent_symbol is Namespace) {
			ccode_params.append_printf ("%scheader_filename = \"%s\"", separator, get_cheaders(m));
			separator = ", ";
		}
		if (!float_equal (m.cinstance_parameter_position, 0)) {
			ccode_params.append_printf ("%sinstance_pos = %g", separator, m.cinstance_parameter_position);
			separator = ", ";
		}
		if (m.no_array_length && m.return_type is ArrayType) {
			ccode_params.append_printf ("%sarray_length = false", separator);
			separator = ", ";
		}
		if (!float_equal (m.carray_length_parameter_position, -3)) {
			ccode_params.append_printf ("%sarray_length_pos = %g", separator, m.carray_length_parameter_position);
			separator = ", ";
		}
		if (m.array_null_terminated && m.return_type is ArrayType) {
			ccode_params.append_printf ("%sarray_null_terminated = true", separator);
			separator = ", ";
		}
		if (!float_equal (m.cdelegate_target_parameter_position, -3)) {
			ccode_params.append_printf ("%sdelegate_target_pos = %g", separator, m.cdelegate_target_parameter_position);
			separator = ", ";
		}
		if (m.vfunc_name != m.name) {
			ccode_params.append_printf ("%svfunc_name = \"%s\"", separator, m.vfunc_name);
			separator = ", ";
		}
		if (m.sentinel != m.DEFAULT_SENTINEL) {
			ccode_params.append_printf ("%ssentinel = \"%s\"", separator, m.sentinel);
			separator = ", ";
		}
		if (m is CreationMethod && ((CreationMethod)m).custom_return_type_cname != null) {
			ccode_params.append_printf ("%stype = \"%s\"", separator, ((CreationMethod)m).custom_return_type_cname);
			separator = ", ";
		}
		if (m is CreationMethod && !m.has_construct_function) {
			ccode_params.append_printf ("%shas_construct_function = false", separator);
			separator = ", ";
		}

		if (ccode_params.len > 0) {
			write_indent ();
			write_string ("[CCode (%s)]".printf (ccode_params.str));
		}
		
		write_indent ();
		write_accessibility (m);
		
		if (m is CreationMethod) {
			var datatype = (TypeSymbol) m.parent_symbol;
			write_identifier (datatype.name);
			if (m.name != "new") {
				write_string (".");
				write_identifier (m.name);
			}
			write_string (" ");
		} else if (m.binding == MemberBinding.STATIC) {
			write_string ("static ");
		} else if (m.binding == MemberBinding.CLASS) {
			write_string ("class ");
		} else if (m.is_abstract) {
			write_string ("abstract ");
		} else if (m.is_virtual) {
			write_string ("virtual ");
		} else if (m.overrides) {
			write_string ("override ");
		}
		
		if (!(m is CreationMethod)) {
			write_return_type (m.return_type);
			write_string (" ");

			write_identifier (m.name);
			write_string (" ");
		}
		
		write_params (m.get_parameters ());
		write_error_domains (m.get_error_types ());

		write_code_block (m.body);

		write_newline ();
	}

	public override void visit_creation_method (CreationMethod m) {
		visit_method (m);
	}

	public override void visit_property (Property prop) {
		if (!check_accessibility (prop) || (prop.base_interface_property != null && !prop.is_abstract && !prop.is_virtual)) {
			return;
		}

		if (prop.no_accessor_method) {
			write_indent ();
			write_string ("[NoAccessorMethod]");
		}
		if (prop.property_type is ArrayType && prop.no_array_length) {
			write_indent ();
			write_string ("[CCode (array_length = false");

			if (prop.array_null_terminated) {
				write_string (", array_null_terminated = true");
			}

			write_string (")]");
		}

		write_indent ();
		write_accessibility (prop);

		if (prop.binding == MemberBinding.STATIC) {
			write_string ("static ");
		} else  if (prop.is_abstract) {
			write_string ("abstract ");
		} else if (prop.is_virtual) {
			write_string ("virtual ");
		} else if (prop.overrides) {
			write_string ("override ");
		}

		write_type (prop.property_type);

		write_string (" ");
		write_identifier (prop.name);
		write_string (" {");
		if (prop.get_accessor != null) {
			if (prop.get_accessor.value_type.is_disposable ()) {
				write_string (" owned");
			}

			write_string (" get");
			write_code_block (prop.get_accessor.body);
		}
		if (prop.set_accessor != null) {
			if (prop.set_accessor.value_type.value_owned) {
				write_string ("owned ");
			}

			if (prop.set_accessor.writable) {
				write_string (" set");
			}
			if (prop.set_accessor.construction) {
				write_string (" construct");
			}
			write_code_block (prop.set_accessor.body);
		}
		write_string (" }");
		write_newline ();
	}

	public override void visit_signal (Signal sig) {
		if (!check_accessibility (sig)) {
			return;
		}
		
		if (sig.has_emitter) {
			write_indent ();
			write_string ("[HasEmitter]");
		}
		
		write_indent ();
		write_accessibility (sig);

		if (sig.is_virtual) {
			write_string ("virtual ");
		}

		write_string ("signal ");
		
		write_return_type (sig.return_type);
		
		write_string (" ");
		write_identifier (sig.name);
		
		write_string (" ");
		
		write_params (sig.get_parameters ());

		write_string (";");

		write_newline ();
	}

	public override void visit_block (Block b) {
		write_begin_block ();

		foreach (Statement stmt in b.get_statements ()) {
			stmt.accept (this);
		}

		write_end_block ();
	}

	public override void visit_empty_statement (EmptyStatement stmt) {
	}

	public override void visit_declaration_statement (DeclarationStatement stmt) {
		write_indent ();
		stmt.declaration.accept (this);
		write_string (";");
		write_newline ();
	}

	public override void visit_local_variable (LocalVariable local) {
		write_type (local.variable_type);
		write_string (" ");
		write_identifier (local.name);
		if (local.initializer != null) {
			write_string (" = ");
			local.initializer.accept (this);
		}
	}

	public override void visit_initializer_list (InitializerList list) {
		write_string ("{");

		bool first = true;
		foreach (Expression initializer in list.get_initializers ()) {
			if (!first) {
				write_string (", ");
			} else {
				write_string (" ");
			}
			first = false;
			initializer.accept (this);
		}
		write_string (" }");
	}

	public override void visit_expression_statement (ExpressionStatement stmt) {
		write_indent ();
		stmt.expression.accept (this);
		write_string (";");
		write_newline ();
	}

	public override void visit_if_statement (IfStatement stmt) {
		write_indent ();
		write_string ("if (");
		stmt.condition.accept (this);
		write_string (")");
		stmt.true_statement.accept (this);
		if (stmt.false_statement != null) {
			write_string (" else");
			stmt.false_statement.accept (this);
		}
		write_newline ();
	}

	public override void visit_switch_statement (SwitchStatement stmt) {
		write_indent ();
		write_string ("switch (");
		stmt.expression.accept (this);
		write_string (") {");
		write_newline ();

		foreach (SwitchSection section in stmt.get_sections ()) {
			section.accept (this);
		}

		write_indent ();
		write_string ("}");
		write_newline ();
	}

	public override void visit_switch_section (SwitchSection section) {
		foreach (SwitchLabel label in section.get_labels ()) {
			label.accept (this);
		}

		visit_block (section);
	}

	public override void visit_switch_label (SwitchLabel label) {
		if (label.expression != null) {
			write_indent ();
			write_string ("case ");
			label.expression.accept (this);
			write_string (":");
			write_newline ();
		} else {
			write_indent ();
			write_string ("default:");
			write_newline ();
		}
	}

	public override void visit_loop (Loop stmt) {
		write_indent ();
		write_string ("loop");
		stmt.body.accept (this);
		write_newline ();
	}

	public override void visit_while_statement (WhileStatement stmt) {
		write_indent ();
		write_string ("while (");
		stmt.condition.accept (this);
		write_string (")");
		stmt.body.accept (this);
		write_newline ();
	}

	public override void visit_do_statement (DoStatement stmt) {
		write_indent ();
		write_string ("do");
		stmt.body.accept (this);
		write_string ("while (");
		stmt.condition.accept (this);
		write_string (");");
		write_newline ();
	}

	public override void visit_for_statement (ForStatement stmt) {
		write_indent ();
		write_string ("for (");

		bool first = true;
		foreach (Expression initializer in stmt.get_initializer ()) {
			if (!first) {
				write_string (", ");
			}
			first = false;
			initializer.accept (this);
		}
		write_string ("; ");

		stmt.condition.accept (this);
		write_string ("; ");

		first = true;
		foreach (Expression iterator in stmt.get_iterator ()) {
			if (!first) {
				write_string (", ");
			}
			first = false;
			iterator.accept (this);
		}

		write_string (")");
		stmt.body.accept (this);
		write_newline ();
	}

	public override void visit_foreach_statement (ForeachStatement stmt) {
	}

	public override void visit_break_statement (BreakStatement stmt) {
		write_indent ();
		write_string ("break;");
		write_newline ();
	}

	public override void visit_continue_statement (ContinueStatement stmt) {
		write_indent ();
		write_string ("continue;");
		write_newline ();
	}

	public override void visit_return_statement (ReturnStatement stmt) {
		write_indent ();
		write_string ("return");
		if (stmt.return_expression != null) {
			write_string (" ");
			stmt.return_expression.accept (this);
		}
		write_string (";");
		write_newline ();
	}

	public override void visit_yield_statement (YieldStatement y) {
		write_indent ();
		write_string ("yield");
		if (y.yield_expression != null) {
			write_string (" ");
			y.yield_expression.accept (this);
		}
		write_string (";");
		write_newline ();
	}

	public override void visit_throw_statement (ThrowStatement stmt) {
		write_indent ();
		write_string ("throw");
		if (stmt.error_expression != null) {
			write_string (" ");
			stmt.error_expression.accept (this);
		}
		write_string (";");
		write_newline ();
	}

	public override void visit_try_statement (TryStatement stmt) {
		write_indent ();
		write_string ("try");
		stmt.body.accept (this);
		write_newline ();
	}

	public override void visit_catch_clause (CatchClause clause) {
	}

	public override void visit_lock_statement (LockStatement stmt) {
	}

	public override void visit_delete_statement (DeleteStatement stmt) {
	}

	public override void visit_array_creation_expression (ArrayCreationExpression expr) {
		write_string ("new ");
		write_type (expr.element_type);
		write_string ("[");

		bool first = true;
		foreach (Expression size in expr.get_sizes ()) {
			if (!first) {
				write_string (", ");
			}
			first = false;

			size.accept (this);
		}

		write_string ("]");

		if (expr.initializer_list != null) {
			write_string (" ");
			expr.initializer_list.accept (this);
		}
	}

	public override void visit_boolean_literal (BooleanLiteral lit) {
		write_string (lit.value.to_string ());
	}

	public override void visit_character_literal (CharacterLiteral lit) {
		write_string (lit.value);
	}

	public override void visit_integer_literal (IntegerLiteral lit) {
		write_string (lit.value);
	}

	public override void visit_real_literal (RealLiteral lit) {
		write_string (lit.value);
	}

	public override void visit_string_literal (StringLiteral lit) {
		write_string (lit.value);
	}

	public override void visit_null_literal (NullLiteral lit) {
		write_string ("null");
	}

	public override void visit_member_access (MemberAccess expr) {
		if (expr.inner != null) {
			expr.inner.accept (this);
			write_string (".");
		}
		write_identifier (expr.member_name);
	}

	public override void visit_method_call (MethodCall expr) {
		expr.call.accept (this);
		write_string (" (");

		bool first = true;
		foreach (Expression arg in expr.get_argument_list ()) {
			if (!first) {
				write_string (", ");
			}
			first = false;

			arg.accept (this);
		}

		write_string (")");
	}
	
	public override void visit_element_access (ElementAccess expr) {
		expr.container.accept (this);
		write_string ("[");

		bool first = true;
		foreach (Expression index in expr.get_indices ()) {
			if (!first) {
				write_string (", ");
			}
			first = false;

			index.accept (this);
		}

		write_string ("]");
	}

	public override void visit_base_access (BaseAccess expr) {
		write_string ("base");
	}

	public override void visit_postfix_expression (PostfixExpression expr) {
		expr.inner.accept (this);
		if (expr.increment) {
			write_string ("++");
		} else {
			write_string ("--");
		}
	}

	public override void visit_object_creation_expression (ObjectCreationExpression expr) {
		write_string ("new ");
		write_type (expr.type_reference);
		write_string (" (");

		bool first = true;
		foreach (Expression arg in expr.get_argument_list ()) {
			if (!first) {
				write_string (", ");
			}
			first = false;

			arg.accept (this);
		}

		write_string (")");
	}

	public override void visit_sizeof_expression (SizeofExpression expr) {
		write_string ("sizeof (");
		write_type (expr.type_reference);
		write_string (")");
	}

	public override void visit_typeof_expression (TypeofExpression expr) {
		write_string ("typeof (");
		write_type (expr.type_reference);
		write_string (")");
	}

	public override void visit_unary_expression (UnaryExpression expr) {
		switch (expr.operator) {
		case UnaryOperator.PLUS:
			write_string ("+");
			break;
		case UnaryOperator.MINUS:
			write_string ("-");
			break;
		case UnaryOperator.LOGICAL_NEGATION:
			write_string ("!");
			break;
		case UnaryOperator.BITWISE_COMPLEMENT:
			write_string ("~");
			break;
		case UnaryOperator.INCREMENT:
			write_string ("++");
			break;
		case UnaryOperator.DECREMENT:
			write_string ("--");
			break;
		case UnaryOperator.REF:
			write_string ("ref ");
			break;
		case UnaryOperator.OUT:
			write_string ("out ");
			break;
		default:
			assert_not_reached ();
		}
		expr.inner.accept (this);
	}

	public override void visit_cast_expression (CastExpression expr) {
		if (!expr.is_silent_cast) {
			write_string ("(");
			write_type (expr.type_reference);
			write_string (") ");
		}

		expr.inner.accept (this);

		if (expr.is_silent_cast) {
			write_string (" as ");
			write_type (expr.type_reference);
		}
	}

	public override void visit_pointer_indirection (PointerIndirection expr) {
		write_string ("*");
		expr.inner.accept (this);
	}

	public override void visit_addressof_expression (AddressofExpression expr) {
		write_string ("&");
		expr.inner.accept (this);
	}

	public override void visit_reference_transfer_expression (ReferenceTransferExpression expr) {
		write_string ("(owned) ");
		expr.inner.accept (this);
	}

	public override void visit_binary_expression (BinaryExpression expr) {
		expr.left.accept (this);

		switch (expr.operator) {
		case BinaryOperator.PLUS:
			write_string (" + ");
			break;
		case BinaryOperator.MINUS:
			write_string (" - ");
			break;
		case BinaryOperator.MUL:
			write_string (" * ");
			break;
		case BinaryOperator.DIV:
			write_string (" / ");
			break;
		case BinaryOperator.MOD:
			write_string (" % ");
			break;
		case BinaryOperator.SHIFT_LEFT:
			write_string (" << ");
			break;
		case BinaryOperator.SHIFT_RIGHT:
			write_string (" >> ");
			break;
		case BinaryOperator.LESS_THAN:
			write_string (" < ");
			break;
		case BinaryOperator.GREATER_THAN:
			write_string (" > ");
			break;
		case BinaryOperator.LESS_THAN_OR_EQUAL:
			write_string (" <= ");
			break;
		case BinaryOperator.GREATER_THAN_OR_EQUAL:
			write_string (" >= ");
			break;
		case BinaryOperator.EQUALITY:
			write_string (" == ");
			break;
		case BinaryOperator.INEQUALITY:
			write_string (" != ");
			break;
		case BinaryOperator.BITWISE_AND:
			write_string (" & ");
			break;
		case BinaryOperator.BITWISE_OR:
			write_string (" | ");
			break;
		case BinaryOperator.BITWISE_XOR:
			write_string (" ^ ");
			break;
		case BinaryOperator.AND:
			write_string (" && ");
			break;
		case BinaryOperator.OR:
			write_string (" || ");
			break;
		case BinaryOperator.IN:
			write_string (" in ");
			break;
		default:
			assert_not_reached ();
		}

		expr.right.accept (this);
	}

	public override void visit_type_check (TypeCheck expr) {
		expr.expression.accept (this);
		write_string (" is ");
		write_type (expr.type_reference);
	}

	public override void visit_conditional_expression (ConditionalExpression expr) {
		expr.condition.accept (this);
		write_string ("?");
		expr.true_expression.accept (this);
		write_string (":");
		expr.false_expression.accept (this);
	}

	public override void visit_lambda_expression (LambdaExpression expr) {
	}

	public override void visit_assignment (Assignment a) {
		a.left.accept (this);
		write_string (" = ");
		a.right.accept (this);
	}

	private void write_indent () {
		int i;
		
		if (!bol) {
			stream.putc ('\n');
		}
		
		for (i = 0; i < indent; i++) {
			stream.putc ('\t');
		}
		
		bol = false;
	}
	
	private void write_identifier (string s) {
		if (s == "base" || s == "break" || s == "class" ||
		    s == "construct" || s == "delegate" || s == "delete" ||
		    s == "do" || s == "dynamic" || s == "foreach" || s == "in" ||
		    s == "interface" || s == "lock" || s == "namespace" ||
		    s == "new" || s == "out" || s == "ref" ||
		    s == "signal" || s.get_char ().isdigit ()) {
			stream.putc ('@');
		}
		write_string (s);
	}

	private void write_return_type (DataType type) {
		if (is_weak (type)) {
			write_string ("unowned ");
		}

		write_type (type);
	}

	private bool is_weak (DataType type) {
		if (type.value_owned) {
			return false;
		} else if (type is VoidType || type is PointerType) {
			return false;
		} else if (type is ValueType) {
			if (type.nullable) {
				// nullable structs are heap allocated
				return true;
			}

			// TODO return true for structs with destroy
			return false;
		}

		return true;
	}

	private void write_type (DataType type) {
		write_string (type.to_qualified_string (current_scope));
	}

	private void write_string (string s) {
		stream.printf ("%s", s);
		bol = false;
	}
	
	private void write_newline () {
		stream.putc ('\n');
		bol = true;
	}
	
	void write_code_block (Block? block) {
		if (block == null || !dump_tree) {
			write_string (";");
			return;
		}

		block.accept (this);
	}

	private void write_begin_block () {
		if (!bol) {
			stream.putc (' ');
		} else {
			write_indent ();
		}
		stream.putc ('{');
		write_newline ();
		indent++;
	}
	
	private void write_end_block () {
		indent--;
		write_indent ();
		stream.printf ("}");
	}

	private bool check_accessibility (Symbol sym) {
		if (dump_tree) {
			return true;
		} else {
		    if (!emit_internal &&
			( sym.access == SymbolAccessibility.PUBLIC ||
			  sym.access == SymbolAccessibility.PROTECTED)) {
			return true;
		    } else if (emit_internal &&
			( sym.access == SymbolAccessibility.INTERNAL ||
			  sym.access == SymbolAccessibility.PUBLIC ||
			  sym.access == SymbolAccessibility.PROTECTED)) {
			return true;
		    }
		}

		return false;
	}

	private void write_attributes (CodeNode node) {
		foreach (Attribute attr in node.attributes) {
			if (!filter_attribute (attr)) {
				write_indent ();
				stream.printf ("[%s", attr.name);

				var keys = attr.args.get_keys ();
				if (keys.size != 0) {
					stream.printf (" (");

					string separator = "";
					foreach (string arg_name in keys) {
						stream.printf ("%s%s = ", separator, arg_name);
						var expr = attr.args.get (arg_name);
						expr.accept (this);
						separator = ", ";
					}

					stream.printf (")");
				}
				stream.printf ("]");
				write_newline ();
			}
		}
	}

	private bool filter_attribute (Attribute attr) {
		if (attr.name == "CCode"
		    || attr.name == "Compact" || attr.name == "Immutable"
		    || attr.name == "SimpleType" || attr.name == "IntegerType" || attr.name == "FloatingType"
		    || attr.name == "Flags") {
			return true;
		}
		return false;
	}

	private void write_accessibility (Symbol sym) {
		if (sym.access == SymbolAccessibility.PUBLIC) {
			write_string ("public ");
		} else if (sym.access == SymbolAccessibility.PROTECTED) {
			write_string ("protected ");
		} else if (sym.access == SymbolAccessibility.INTERNAL) {
			write_string ("internal ");
		} else if (sym.access == SymbolAccessibility.PRIVATE) {
			write_string ("private ");
		}
	}
}
