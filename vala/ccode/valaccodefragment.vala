/* valaccodefragment.vala
 *
 * Copyright (C) 2006  Jürg Billeter
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.

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
 */

using GLib;

/**
 * Represents a container for C code nodes.
 */
public class Vala.CCodeFragment : CCodeNode {
	private List<CCodeNode> children;
	
	/**
	 * Appends the specified code node to this code fragment.
	 *
	 * @param node a C code node
	 */
	public void append (CCodeNode! node) {
		children.append (node);
	}
	
	/**
	 * Returns a copy of the list of children.
	 *
	 * @return children list
	 */
	public ref List<CCodeNode> get_children () {
		return children.copy ();
	}

	public override void write (CCodeWriter! writer) {
		foreach (CCodeNode node in children) {
			node.write (writer);
		}
	}
}
