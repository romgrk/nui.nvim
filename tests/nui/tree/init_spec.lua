pcall(require, "luacov")

local Tree = require("nui.tree")
local h = require("tests.nui")

local eq = h.eq

describe("nui.tree", function()
  local winid, bufnr

  before_each(function()
    winid = vim.api.nvim_get_current_win()
    bufnr = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_win_set_buf(winid, bufnr)
  end)

  it("throws if no winid", function()
    local ok, err = pcall(Tree, {})
    eq(ok, false)
    eq(type(err), "string")
  end)

  it("throws if invalid winid", function()
    local ok, err = pcall(Tree, { winid = 999 })
    eq(ok, false)
    eq(type(err), "string")
  end)

  it("throws on duplicated node id", function()
    local ok, err = pcall(Tree, {
      winid = winid,
      nodes = {
        Tree.Node({ id = "id", text = "text" }),
        Tree.Node({ id = "id", text = "text" }),
      },
    })
    eq(ok, false)
    eq(type(err), "string")
  end)

  it("sets t.winid and t.bufnr properly", function()
    local tree = Tree({ winid = winid })

    eq(winid, tree.winid)
    eq(bufnr, tree.bufnr)
  end)

  it("sets default buf options emulating scratch-buffer", function()
    local tree = Tree({ winid = winid })

    h.assert_buf_options(tree.bufnr, {
      bufhidden = "hide",
      buflisted = false,
      buftype = "nofile",
      swapfile = false,
    })
  end)

  it("sets default win options for handling folds", function()
    local tree = Tree({ winid = winid })

    h.assert_win_options(tree.winid, {
      foldmethod = "manual",
      foldcolumn = "0",
      wrap = false,
    })
  end)

  it("sets t.ns_id if o.ns_id is string", function()
    local ns = "NuiTreeTest"
    local tree = Tree({ winid = winid, ns_id = ns })

    local namespaces = vim.api.nvim_get_namespaces()

    eq(tree.ns_id, namespaces[ns])
  end)

  it("sets t.ns_id if o.ns_id is number", function()
    local ns = "NuiTreeTest"
    local ns_id = vim.api.nvim_create_namespace(ns)
    local tree = Tree({ winid = winid, ns_id = ns_id })

    eq(tree.ns_id, ns_id)
  end)

  it("uses o.get_node_id if provided", function()
    local node_d2 = Tree.Node({ key = "depth two" })
    local node_d1 = Tree.Node({ key = "depth one" }, { node_d2 })
    Tree({
      winid = winid,
      nodes = { node_d1 },
      get_node_id = function(node)
        return node.key
      end,
    })

    eq(node_d1:get_id(), node_d1.key)
    eq(node_d2:get_id(), node_d2.key)
  end)

  describe("default get_node_id", function()
    it("returns id using n.id", function()
      local node = Tree.Node({ id = "id", text = "text" })
      Tree({ winid = winid, nodes = { node } })

      eq(node:get_id(), "-id")
    end)

    it("returns id using parent_id + depth + n.text", function()
      local node_d2 = Tree.Node({ text = "depth two" })
      local node_d1 = Tree.Node({ text = "depth one" }, { node_d2 })
      Tree({ winid = winid, nodes = { node_d1 } })

      eq(node_d1:get_id(), string.format("-%s-%s", node_d1:get_depth(), node_d1.text))
      eq(node_d2:get_id(), string.format("%s-%s-%s", node_d2:get_parent_id(), node_d2:get_depth(), node_d2.text))
    end)

    it("returns id using random number", function()
      math.randomseed(0)
      local expected_id = "-" .. math.random()
      math.randomseed(0)

      local node = Tree.Node({})
      Tree({ winid = winid, nodes = { node } })

      eq(node:get_id(), expected_id)
    end)
  end)

  it("uses o.prepare_node if provided", function()
    local function prepare_node(node, parent_node)
      if not parent_node then
        return node.text
      end

      return parent_node.text .. ":" .. node.text
    end

    local nodes = {
      Tree.Node({ text = "a" }),
      Tree.Node({ text = "b" }, {
        Tree.Node({ text = "b-1" }),
        Tree.Node({ text = "b-2" }),
      }),
      Tree.Node({ text = "c" }),
    }

    nodes[2]:expand()

    local tree = Tree({
      winid = winid,
      nodes = nodes,
      prepare_node = prepare_node,
    })

    tree:render()

    h.assert_buf_lines(tree.bufnr, {
      "a",
      "b",
      "b:b-1",
      "b:b-2",
      "c",
    })
  end)

  describe("default prepare_node", function()
    it("throws if missing n.text", function()
      local nodes = {
        Tree.Node({ txt = "a" }),
        Tree.Node({ txt = "b" }),
        Tree.Node({ txt = "c" }),
      }

      local tree = Tree({
        winid = winid,
        nodes = nodes,
      })

      local ok, err = pcall(tree.render, tree)
      eq(ok, false)
      eq(type(err), "string")
    end)

    it("uses n.text", function()
      local nodes = {
        Tree.Node({ text = "a" }),
        Tree.Node({ text = "b" }),
        Tree.Node({ text = "c" }),
      }

      local tree = Tree({
        winid = winid,
        nodes = nodes,
      })

      tree:render()

      h.assert_buf_lines(
        tree.bufnr,
        vim.tbl_map(function(node)
          return "  " .. node.text
        end, nodes)
      )
    end)

    it("renders arrow if children are present", function()
      local nodes = {
        Tree.Node({ text = "a" }),
        Tree.Node({ text = "b" }, {
          Tree.Node({ text = "b-1" }),
        }),
        Tree.Node({ text = "c" }),
      }
      local tree = Tree({
        winid = winid,
        nodes = nodes,
      })

      tree:render()

      h.assert_buf_lines(tree.bufnr, {
        "  a",
        " b",
        "  c",
      })

      nodes[2]:expand()
      tree:render()

      h.assert_buf_lines(tree.bufnr, {
        "  a",
        " b",
        "    b-1",
        "  c",
      })
    end)
  end)

  describe("method :get_node", function()
    it("can get node under cursor", function()
      local nodes = {
        Tree.Node({ text = "a" }),
        Tree.Node({ text = "b" }),
        Tree.Node({ text = "c" }),
      }

      local tree = Tree({
        winid = winid,
        nodes = nodes,
      })

      tree:render()

      local linenr = 3

      vim.api.nvim_win_set_cursor(winid, { linenr, 0 })

      eq({ tree:get_node() }, { nodes[3], linenr })
    end)

    it("can get node with id", function()
      local b_node_children = {
        Tree.Node({ text = "b-1" }),
        Tree.Node({ text = "b-2" }),
      }

      local nodes = {
        Tree.Node({ text = "a" }),
        Tree.Node({ text = "b" }, b_node_children),
        Tree.Node({ text = "c" }),
      }

      local tree = Tree({
        winid = winid,
        nodes = nodes,
        get_node_id = function(node)
          return node.text
        end,
      })

      tree:render()

      eq({ tree:get_node("b") }, { nodes[2], 2 })

      tree:get_node("b"):expand()
      tree:render()

      eq({ tree:get_node("b-2") }, { b_node_children[2], 4 })
    end)

    it("can get node on linenr", function()
      local nodes = {
        Tree.Node({ text = "a" }),
        Tree.Node({ text = "b" }),
        Tree.Node({ text = "c" }),
      }

      local tree = Tree({
        winid = winid,
        nodes = nodes,
      })

      tree:render()

      local linenr = 1

      eq({ tree:get_node(linenr) }, { nodes[1], linenr })
    end)
  end)

  describe("method :get_nodes", function()
    it("can get nodes at root", function()
      local nodes = {
        Tree.Node({ text = "a" }),
        Tree.Node({ text = "b" }, {
          Tree.Node({ text = "b-1" }),
        }),
      }

      local tree = Tree({
        winid = winid,
        nodes = nodes,
        get_node_id = function(node)
          return node.text
        end,
      })

      eq(tree:get_nodes(), nodes)
    end)

    it("can get nodes under parent node", function()
      local child_nodes = {
        Tree.Node({ text = "b-1" }),
      }

      local tree = Tree({
        winid = winid,
        nodes = {
          Tree.Node({ text = "a" }),
          Tree.Node({ text = "b" }, child_nodes),
        },
        get_node_id = function(node)
          return node.text
        end,
      })

      eq(tree:get_nodes("b"), child_nodes)
    end)
  end)

  describe("method :add_node", function()
    it("throw if invalid parent_id", function()
      local tree = Tree({
        winid = winid,
        nodes = {
          Tree.Node({ text = "x" }),
        },
      })

      local ok, err = pcall(tree.add_node, tree, Tree.Node({ text = "y" }), "invalid_parent_id")
      eq(ok, false)
      eq(type(err), "string")
    end)

    it("can add node at root", function()
      local tree = Tree({
        winid = winid,
        nodes = {
          Tree.Node({ text = "x" }),
        },
      })

      tree:add_node(Tree.Node({ text = "y" }))

      tree:render()

      h.assert_buf_lines(tree.bufnr, {
        "  x",
        "  y",
      })

      tree:add_node(Tree.Node({ text = "z" }))

      tree:render()

      h.assert_buf_lines(tree.bufnr, {
        "  x",
        "  y",
        "  z",
      })
    end)

    it("can add node under parent node", function()
      local nodes = {
        Tree.Node({ text = "a" }),
        Tree.Node({ text = "b" }, {
          Tree.Node({ text = "b-1" }),
        }),
        Tree.Node({ text = "c" }),
      }

      local tree = Tree({
        winid = winid,
        nodes = nodes,
        get_node_id = function(node)
          return node.text
        end,
      })

      tree:add_node(Tree.Node({ text = "b-2" }), "b")

      tree:get_node("b"):expand()

      tree:add_node(Tree.Node({ text = "c-1" }), "c")

      tree:get_node("c"):expand()

      tree:render()

      h.assert_buf_lines(tree.bufnr, {
        "  a",
        " b",
        "    b-1",
        "    b-2",
        " c",
        "    c-1",
      })
    end)
  end)

  describe("method :set_nodes", function()
    it("throw if invalid parent_id", function()
      local tree = Tree({
        winid = winid,
        nodes = {
          Tree.Node({ text = "x" }),
        },
      })

      local ok, err = pcall(tree.set_nodes, tree, {}, "invalid_parent_id")
      eq(ok, false)
      eq(type(err), "string")
    end)

    it("can set nodes at root", function()
      local tree = Tree({
        winid = winid,
        nodes = {
          Tree.Node({ text = "x" }),
        },
      })

      tree:set_nodes({
        Tree.Node({ text = "a" }),
        Tree.Node({ text = "b" }),
      })

      tree:render()

      h.assert_buf_lines(tree.bufnr, {
        "  a",
        "  b",
      })

      tree:set_nodes({
        Tree.Node({ text = "c" }),
      })

      tree:render()

      h.assert_buf_lines(tree.bufnr, {
        "  c",
      })
    end)

    it("can set nodes under parent node", function()
      local nodes = {
        Tree.Node({ text = "a" }),
        Tree.Node({ text = "b" }, {
          Tree.Node({ text = "b-1" }),
        }),
        Tree.Node({ text = "c" }),
      }

      local tree = Tree({
        winid = winid,
        nodes = nodes,
        get_node_id = function(node)
          return node.text
        end,
      })

      tree:set_nodes({
        Tree.Node({ text = "b-2" }),
      }, "b")

      tree:get_node("b"):expand()

      tree:set_nodes({
        Tree.Node({ text = "c-1" }),
        Tree.Node({ text = "c-2" }),
      }, "c")

      tree:get_node("c"):expand()

      tree:render()

      h.assert_buf_lines(tree.bufnr, {
        "  a",
        " b",
        "    b-2",
        " c",
        "    c-1",
        "    c-2",
      })
    end)
  end)

  describe("method :remove_node", function()
    it("can remove node w/o parent", function()
      local nodes = {
        Tree.Node({ text = "a" }),
        Tree.Node({ text = "b" }, {
          Tree.Node({ text = "b-1" }),
        }),
        Tree.Node({ text = "c" }),
      }

      local tree = Tree({
        winid = winid,
        nodes = nodes,
        get_node_id = function(node)
          return node.text
        end,
      })

      tree:remove_node("a")

      tree:get_node("b"):expand()

      tree:render()

      eq(
        vim.tbl_map(function(node)
          return node:get_id()
        end, tree:get_nodes()),
        { "b", "c" }
      )

      h.assert_buf_lines(tree.bufnr, {
        " b",
        "    b-1",
        "  c",
      })
    end)

    it("can remove node w/ parent", function()
      local nodes = {
        Tree.Node({ text = "a" }),
        Tree.Node({ text = "b" }, {
          Tree.Node({ text = "b-1" }),
        }),
        Tree.Node({ text = "c" }),
      }

      local tree = Tree({
        winid = winid,
        nodes = nodes,
        get_node_id = function(node)
          return node.text
        end,
      })

      tree:remove_node("b-1")

      tree:render()

      eq(tree:get_node("b"):get_child_ids(), {})

      h.assert_buf_lines(tree.bufnr, {
        "  a",
        "  b",
        "  c",
      })
    end)
  end)

  describe("method :render", function()
    it("handles unexpected case of missing node", function()
      local nodes = {
        Tree.Node({ text = "a" }),
        Tree.Node({ text = "b" }),
        Tree.Node({ text = "c" }),
      }

      local tree = Tree({
        winid = winid,
        nodes = nodes,
        get_node_id = function(node)
          return node.text
        end,
      })

      -- this should not happen normally
      tree.nodes.by_id["a"] = nil

      tree:render()

      h.assert_buf_lines(tree.bufnr, {
        "  b",
        "  c",
      })
    end)
  end)
end)

describe("nui.tree.Node", function()
  describe("method :has_children", function()
    it("works before initialization", function()
      local node_wo_children = Tree.Node({ text = "a" })
      local node_w_children = Tree.Node({ text = "b" }, { Tree.Node({ text = "b-1" }) })

      eq(node_wo_children._initialized, false)
      eq(node_wo_children:has_children(), false)

      eq(node_w_children._initialized, false)
      eq(type(node_w_children.__children), "table")
      eq(node_w_children:has_children(), true)
    end)

    it("works after initialization", function()
      local node_wo_children = Tree.Node({ text = "a" })
      local node_w_children = Tree.Node({ text = "b" }, { Tree.Node({ text = "b-1" }) })

      Tree({
        winid = vim.api.nvim_get_current_win(),
        nodes = { node_wo_children, node_w_children },
      })

      eq(node_wo_children._initialized, true)
      eq(node_wo_children:has_children(), false)

      eq(node_w_children._initialized, true)
      eq(type(node_w_children.__children), "nil")
      eq(node_w_children:has_children(), true)
    end)
  end)

  describe("method :expand", function()
    it("returns true if not already expanded", function()
      local node = Tree.Node({ text = "b" }, { Tree.Node({ text = "b-1" }) })
      eq(node:is_expanded(), false)
      eq(node:expand(), true)
      eq(node:is_expanded(), true)
    end)

    it("returns false if already expanded", function()
      local node = Tree.Node({ text = "b" }, { Tree.Node({ text = "b-1" }) })
      node:expand()
      eq(node:is_expanded(), true)
      eq(node:expand(), false)
      eq(node:is_expanded(), true)
    end)

    it("does not work w/o children", function()
      local node = Tree.Node({ text = "a" })
      eq(node:is_expanded(), false)
      eq(node:expand(), false)
      eq(node:is_expanded(), false)
    end)
  end)

  describe("method :collapse", function()
    it("returns true if not already collapsed", function()
      local node = Tree.Node({ text = "b" }, { Tree.Node({ text = "b-1" }) })
      node:expand()
      eq(node:is_expanded(), true)
      eq(node:collapse(), true)
      eq(node:is_expanded(), false)
    end)

    it("returns false if already collapsed", function()
      local node = Tree.Node({ text = "b" }, { Tree.Node({ text = "b-1" }) })
      eq(node:is_expanded(), false)
      eq(node:collapse(), false)
      eq(node:is_expanded(), false)
    end)

    it("does not work w/o children", function()
      local node = Tree.Node({ text = "a" })
      eq(node:is_expanded(), false)
      eq(node:collapse(), false)
      eq(node:is_expanded(), false)
    end)
  end)
end)
