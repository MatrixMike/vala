/* generator.vala
 *
 * Copyright (C) 2010 Luca Bruno
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Luca Bruno <lethalman88@gmail.com>
 */

using Valadoc;
using Valadoc.Api;
using Valadoc.Content;

public class Gtkdoc.Generator : Api.Visitor {
	class FileData {
		public string filename;
		public Gee.List<string> comments;
		public Gee.List<string> section_lines;
	}

	public Gee.List<DBus.Interface> dbus_interfaces = new Gee.LinkedList<DBus.Interface>();

	private Settings settings;
	private Gee.Map<string, FileData> files_data = new Gee.HashMap<string, FileData>();
	private string current_cname;
	private Gee.List<Header> current_headers;
	private Class current_class;
	private Method current_method;
	private Delegate current_delegate;
	private Api.Signal current_signal;
	private DBus.Interface current_dbus_interface;
	private DBus.Member current_dbus_member;

	public bool execute (Settings settings, Api.Tree tree) {
		this.settings = settings;
		tree.accept (this);
		var code_dir = Path.build_filename (settings.path, "ccomments");
		var sections = Path.build_filename (settings.path, "%s-sections.txt".printf (settings.pkg_name));
		DirUtils.create_with_parents (code_dir, 0777);

		var sections_writer = new TextWriter (sections, "a");
		if (!sections_writer.open ()) {
			warning ("GtkDoc: unable to open %s for writing", sections_writer.filename);
			return false;
		}

		foreach (var file_data in files_data.values) {
			// C comments
			var basename = get_section (file_data.filename);
			var cwriter = new TextWriter (Path.build_filename (code_dir, "%s.c".printf (basename)), "w");

			if (!cwriter.open ()) {
				warning ("GtkDoc: unable to open %s for writing", cwriter.filename);
				return false;
			}

			foreach (var comment in file_data.comments) {
				cwriter.write_line (comment);
			}
			cwriter.close ();

			// sections
			sections_writer.write_line ("<SECTION>");
			sections_writer.write_line ("<FILE>%s</FILE>".printf (basename));

			foreach (var section_line in file_data.section_lines) {
				sections_writer.write_line (section_line);
			}
			sections_writer.write_line ("</SECTION>");
		}
		sections_writer.close ();

		return true;
	}

	public Gee.Set<string> get_filenames () {
		return files_data.keys.read_only_view;
	}

	private FileData get_file_data (string filename) {
		var file_data = files_data[filename];
		if (file_data == null) {
			file_data = new FileData ();
			file_data.filename = filename;
			file_data.comments = new Gee.LinkedList<string>();
			file_data.section_lines = new Gee.LinkedList<string>();
			files_data[filename] = file_data;
		}
		return file_data;
	}

	private Gee.List<Header> merge_headers (Gee.List<Header> doc_headers, Gee.List<Header>? lang_headers) {
		if (lang_headers == null) {
			return doc_headers;
		}

		var headers = new Gee.LinkedList<Header>();

		foreach (var doc_header in doc_headers) {
			var header = doc_header;
			foreach (var lang_header in lang_headers) {
				if (doc_header.name == lang_header.name) {
					header.annotations = lang_header.annotations;
					if (lang_header.value != null) {
						header.value += "<para>%s</para>".printf (lang_header.value);
					}
				}
			}
			headers.add (header);
		}

		// add remaining headers
		foreach (var lang_header in lang_headers) {
			bool found = false;

			foreach (var header in headers) {
				if (header.name == lang_header.name) {
					found = true;
					break;
				}
			}

			if (!found && lang_header.value != null) {
				headers.add (lang_header);
			}
		}
		return headers;
	}

	private GComment create_gcomment (string symbol, Comment? comment, bool short_description = false, string[]? returns_annotations = null, bool is_dbus = false) {
		var converter = new Gtkdoc.CommentConverter ();
		if (comment != null) {
			converter.convert (comment, is_dbus);
		}

		var gcomment = new GComment ();
		gcomment.symbol = symbol;
		gcomment.returns = converter.returns;
		gcomment.returns_annotations = returns_annotations;

		if (converter.brief_comment != null && short_description) {
			var header = new Header ("@short_description", converter.brief_comment);
			gcomment.headers.add (header);
		} else {
			gcomment.brief_comment = converter.brief_comment;
		}
		gcomment.long_comment = converter.long_comment;

		gcomment.headers.add_all (merge_headers (converter.headers, current_headers));
		gcomment.versioning.add_all (converter.versioning);
		return gcomment;
	}

	private void add_comment (string filename, string symbol, Comment? comment, bool short_description = false) {
		if (comment == null) {
			return;
		}

		var file_data = get_file_data (filename);
		file_data.comments.add (create_gcomment(symbol, comment, short_description).to_string ());
	}

	private GComment? add_symbol (string filename, string cname, Comment? comment = null, string? symbol = null, bool title = false, bool short_description = false, string[]? returns_annotations = null) {
		var file_data = get_file_data (filename);
		if (title) {
			file_data.section_lines.add ("<TITLE>%s</TITLE>".printf (cname));
		}

		file_data.section_lines.add (cname);

		if (comment != null || (current_headers != null && current_headers.size > 0)) {
			var gcomment = create_gcomment(symbol ?? cname, comment, short_description, returns_annotations);
			file_data.comments.add (gcomment.to_string ());
			return gcomment;
		}
		return null;
	}

	private Header? add_custom_header (string name, string? comment, string[]? annotations = null) {
		if (comment == null && annotations == null) {
			return null;
		}

		var header = new Header ("@"+name);
		header.annotations = annotations;
		header.value = comment;
		current_headers.add (header);
		return header;
	}

	private void remove_custom_header (string name) {
		var header_name = "@%s".printf (name);
		var it = current_headers.iterator();
		while (it.next ()) {
			var header = it.@get ();
			if (header.name == header_name) {
				it.remove ();
				break;
			}
		}
	}

	private Header? add_header (string name, Comment? comment, string[]? annotations = null) {
		if (comment == null && annotations == null) {
			return null;
		}

		var converter = new Gtkdoc.CommentConverter ();
		var header = new Header ("@"+name);

		if (comment != null) {
			converter.convert (comment);
			if (converter.brief_comment != null) {
				header.value = converter.brief_comment;
				if (converter.long_comment != null) {
					header.value += converter.long_comment;
				}
			}
		}

		header.annotations = annotations;
		current_headers.add (header);
		return header;
	}

	public override void visit_tree (Api.Tree tree) {
		tree.accept_children (this);
	}

	public override void visit_package (Api.Package package) {
		/* we are not (yet?) interested in external packages */
		if (package.is_package) {
			return;
		}

		package.accept_all_children (this);
	}

	public override void visit_namespace (Api.Namespace ns) {
		if (ns.get_filename () != null) {
			add_comment (ns.get_filename(), "SECTION:%s".printf (get_section (ns.get_filename ())), ns.documentation, true);
		}

		ns.accept_all_children (this);
	}

	public override void visit_interface (Api.Interface iface) {
		var old_cname = current_cname;
		var old_headers = current_headers;
		var old_dbus_interface = current_dbus_interface;
		current_cname = iface.get_cname ();
		current_headers = new Gee.LinkedList<Header>();
		current_dbus_interface = null;

		if (iface.get_dbus_name () != null) {
			current_dbus_interface = new DBus.Interface (settings.pkg_name, iface.get_dbus_name ());
		}
		iface.accept_all_children (this);
		add_symbol (iface.get_filename(), iface.get_cname(), iface.documentation, null, true);
		if (current_dbus_interface != null) {
			current_dbus_interface.write (settings);
			dbus_interfaces.add (current_dbus_interface);
		}

		current_cname = old_cname;
		current_headers = old_headers;
		current_dbus_interface = old_dbus_interface;
	}

	public override void visit_class (Api.Class cl) {
		var old_cname = current_cname;
		var old_headers = current_headers;
		var old_class = current_class;
		var old_dbus_interface = current_dbus_interface;
		current_cname = cl.get_cname ();
		current_headers = new Gee.LinkedList<Header>();
		current_class = cl;
		current_dbus_interface = null;

		if (cl.get_dbus_name () != null) {
			current_dbus_interface = new DBus.Interface (settings.pkg_name, cl.get_dbus_name ());
		}
		cl.accept_all_children (this);
		add_symbol (cl.get_filename(), cl.get_cname(), cl.documentation, null, true);
		if (current_dbus_interface != null) {
			current_dbus_interface.write (settings);
			dbus_interfaces.add (current_dbus_interface);
		}

		current_cname = old_cname;
		current_headers = old_headers;
		current_class = old_class;
		current_dbus_interface = old_dbus_interface;

		if (cl.is_fundamental && cl.base_type == null) {
			var filename = cl.get_filename ();
			add_symbol (filename, cl.get_ref_function_cname ());
			add_symbol (filename, cl.get_unref_function_cname ());
			add_symbol (filename, cl.get_param_spec_function_cname ());
			add_symbol (filename, cl.get_set_value_function_cname ());
			add_symbol (filename, cl.get_get_value_function_cname ());
			add_symbol (filename, cl.get_take_value_function_cname ());
		}
	}

	public override void visit_struct (Api.Struct st) {
		var old_cname = current_cname;
		var old_headers = current_headers;
		current_cname = st.get_cname ();
		current_headers = new Gee.LinkedList<Header>();

		st.accept_all_children (this);
		add_symbol (st.get_filename(), st.get_cname(), st.documentation);

		current_cname = old_cname;
		current_headers = old_headers;

		add_symbol (st.get_filename(), st.get_dup_function_cname ());
		add_symbol (st.get_filename(), st.get_free_function_cname ());
	}

	public override void visit_error_domain (Api.ErrorDomain edomain) {
		if (current_method != null || current_delegate != null) {
			// method throws error
			Header? param_header = null;
			foreach (var header in current_headers) {
				if (header.name == "error") {
					param_header = header;
					break;
				}
			}
			if (param_header == null) {
				add_custom_header ("error", "location to store the error occuring, or %NULL to ignore", {"error-domains %s".printf (edomain.get_cname ())});
			} else {
				// assume the only annotation is error-domains
				var annotation = param_header.annotations[0];
				annotation += " %s".printf (edomain.get_cname ());
				param_header.annotations[0] = annotation;
			}
		} else {
			// error domain definition
			var old_headers = current_headers;
			current_headers = new Gee.LinkedList<Header>();

			edomain.accept_all_children (this);
			add_symbol (edomain.get_filename(), edomain.get_cname(), edomain.documentation);

			current_headers = old_headers;
		}
	}

	public override void visit_error_code (Api.ErrorCode ecode) {
		add_header (ecode.get_cname (), ecode.documentation);
		ecode.accept_all_children (this);
	}

	public override void visit_enum (Api.Enum en) {
		var old_headers = current_headers;
		current_headers = new Gee.LinkedList<Header>();

		en.accept_all_children (this);
		add_symbol (en.get_filename(), en.get_cname(), en.documentation);

		current_headers = old_headers;
	}

	public override void visit_enum_value (Api.EnumValue eval) {
		add_header (eval.get_cname (), eval.documentation);
		eval.accept_all_children (this);
	}

	public override void visit_property (Api.Property prop) {
		if (prop.is_override || prop.is_private || (!prop.is_abstract && !prop.is_virtual && prop.base_property != null)) {
			return;
		}

		add_comment (prop.get_filename(), "%s:%s".printf (current_cname, prop.get_cname ()), prop.documentation);
		prop.accept_all_children (this);

		if (prop.getter != null && !prop.getter.is_private && prop.getter.is_get) {
			add_symbol (prop.get_filename(), prop.getter.get_cname ());
		}

		if (prop.setter != null && !prop.setter.is_private && prop.setter.is_set) {
			add_symbol (prop.get_filename(), prop.setter.get_cname ());
		}
	}

	public override void visit_field (Api.Field f) {
		if (f.is_private) {
			return;
		}

		if (current_headers == null) {
			// field not in class/struct/interface
			add_symbol (f.get_filename(), f.get_cname(), f.documentation);
		} else {
			add_header (f.get_cname (), f.documentation);
		}
		f.accept_all_children (this);
	}

	public override void visit_constant (Api.Constant c) {
		add_symbol (c.get_filename(), c.get_cname(), c.documentation);
		c.accept_all_children (this);
	}

	public override void visit_delegate (Api.Delegate d) {
		var old_headers = current_headers;
		var old_delegate = current_delegate;
		current_headers = new Gee.LinkedList<Header>();
		current_delegate = d;

		d.accept_all_children (this);
		add_symbol (d.get_filename(), d.get_cname(), d.documentation);

		current_headers = old_headers;
		current_delegate = old_delegate;
	}

	public override void visit_signal (Api.Signal sig) {
		var old_headers = current_headers;
		var old_signal = current_signal;
		var old_dbus_member = current_dbus_member;
		current_headers = new Gee.LinkedList<Header>();
		current_signal = sig;
		current_dbus_member = null;

		if (current_dbus_interface != null && sig.is_dbus_visible) {
			current_dbus_member = new DBus.Member (sig.get_dbus_name ());
		}
		// gtkdoc maps parameters by their ordering, so let's customly add the first parameter
		add_custom_header (to_lower_case (((Api.Node)sig.parent).name), "", null);

		sig.accept_all_children (this);

		var name = sig.get_cname().replace ("_", "-");
		add_comment (sig.get_filename(), "%s::%s".printf (current_cname, name), sig.documentation);
		if (current_dbus_interface != null && sig.is_dbus_visible) {
			// remove the custom header
			remove_custom_header (to_lower_case (((Api.Node)sig.parent).name));
			var gcomment = create_gcomment (sig.get_dbus_name (), sig.documentation, false, null, true);
			current_dbus_member.comment = gcomment;
			current_dbus_interface.add_signal (current_dbus_member);
		}

		current_headers = old_headers;
		current_signal = old_signal;
		current_dbus_member = old_dbus_member;
	}

	public override void visit_method (Api.Method m) {
		if ((m.is_constructor && current_class.is_abstract) || m.is_override || m.is_private || (!m.is_abstract && !m.is_virtual && m.base_method != null)) {
			return;
		}

		var annotations = new string[]{};

		if (m.return_type != null) {
			if (m.return_type.data_type is Api.Array) {
				annotations += "array length=result_length1";
			}

			if (m.return_type.is_unowned) {
				annotations += "transfer none";
			}
		}

		var old_headers = current_headers;
		var old_method = current_method;
		var old_dbus_member = current_dbus_member;
		current_headers = new Gee.LinkedList<Header>();
		current_method = m;
		current_dbus_member = null;

		if (current_dbus_interface != null && m.is_dbus_visible && !m.is_constructor) {
			current_dbus_member = new DBus.Member (m.get_dbus_name ());
		}

		m.accept_all_children (this);

		if (m.is_yields) {
			add_custom_header ("_callback_", "callback to call when the request is satisfied", {"scope async"});
			add_custom_header ("user_data", "the data to pass to callback function", {"closure"});
		}
		add_symbol (m.get_filename(), m.get_cname (), m.documentation, null, false, false, annotations);
		if (current_dbus_interface != null && m.is_dbus_visible && !m.is_constructor) {
			if (m.return_type != null && m.return_type.data_type != null) {
				var dresult = new DBus.Parameter (m.get_dbus_result_name (), m.return_type.get_dbus_type_signature (), DBus.Parameter.Direction.OUT);
				current_dbus_member.add_parameter (dresult);
			}
			var gcomment = create_gcomment (m.get_dbus_name (), m.documentation, false, null, true);
			current_dbus_member.comment = gcomment;
			current_dbus_interface.add_method (current_dbus_member);
		}

		current_headers = old_headers;
		current_method = old_method;
		current_dbus_member = old_dbus_member;

		if (m.is_yields) {
			add_symbol (m.get_filename(), m.get_finish_function_cname ());
		}
	}

	public override void visit_formal_parameter (Api.FormalParameter param) {
		var annotations = new string[]{};
		var direction = "in";

		if (param.is_out) {
			direction = "out";
		} else if (param.is_ref) {
			direction = "inout";
		}
		annotations += direction;

		if (param.parameter_type.is_nullable) {
			annotations += "allow-none";
		}

		if (param.parameter_type.is_owned) {
			annotations += "transfer full";
		}

		if (param.parameter_type.data_type is Api.Array) {
			annotations += "array length=%s".printf (param.name+"_length1");
		}

		if (get_cname (param.parameter_type.data_type) == "GError") {
			annotations += "not-error";
		}

		if (current_signal != null && param.documentation == null) {
			// gtkdoc writes arg0, arg1 which is ugly. As a workaround, we always add an header for them.
			add_custom_header (param.name, "", null);
		} else {
			add_header (param.name, param.documentation, annotations);
		}

		if (current_dbus_member != null) {
			var ddirection = DBus.Parameter.Direction.IN;
			if (current_signal != null) {
				ddirection = DBus.Parameter.Direction.NONE;
			} else if (param.is_out) {
				ddirection = DBus.Parameter.Direction.OUT;
			}
			var dparam = new DBus.Parameter (param.name, param.parameter_type.get_dbus_type_signature (), ddirection);
			current_dbus_member.add_parameter (dparam);
		}
		param.accept_all_children (this);
	}
}
