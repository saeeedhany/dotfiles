local map = vim.keymap.set

vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- File
map('n', '<C-s>', '<cmd>w<cr>',  { desc = 'Save' })
map('n', '<C-q>', '<cmd>q<cr>',  { desc = 'Quit' })

-- Escape
map({ 'i', 'v', 's' }, 'kj', '<Esc>',       { desc = 'Exit mode' })
map('n', '<Esc>',            '<cmd>nohl<cr>', { desc = 'Clear search highlight' })

-- Windows
map('n', '<C-h>', '<C-w>h', { desc = 'Window left' })
map('n', '<C-j>', '<C-w>j', { desc = 'Window down' })
map('n', '<C-k>', '<C-w>k', { desc = 'Window up' })
map('n', '<C-l>', '<C-w>l', { desc = 'Window right' })

-- Buffers
map('n', '<Tab>',   '<cmd>bnext<cr>',     { desc = 'Next buffer' })
map('n', '<S-Tab>', '<cmd>bprevious<cr>', { desc = 'Prev buffer' })
map('n', '<C-w>',   function() require('mini.bufremove').delete() end,        { desc = 'Delete buffer' })
map('n', '<C-S-w>', function() require('mini.bufremove').delete(0, true) end, { desc = 'Force delete buffer' })

-- Editing
map('v', '<', '<gv',               { desc = 'Indent left' })
map('v', '>', '>gv',               { desc = 'Indent right' })
map('v', 'J', ":m '>+1<cr>gv=gv", { desc = 'Move lines down' })
map('v', 'K', ":m '<-2<cr>gv=gv", { desc = 'Move lines up' })

-- Navigation
map('n', '<C-d>', '<C-d>zz', { desc = 'Scroll down (centered)' })
map('n', '<C-u>', '<C-u>zz', { desc = 'Scroll up (centered)' })
map('n', 'n',     'nzzzv',   { desc = 'Next result (centered)' })
map('n', 'N',     'Nzzzv',   { desc = 'Prev result (centered)' })

-- LSP
map('n', 'gd', vim.lsp.buf.definition,     { desc = 'Definition' })
map('n', 'gD', vim.lsp.buf.declaration,    { desc = 'Declaration' })
map('n', 'gi', vim.lsp.buf.implementation, { desc = 'Implementation' })
map('n', 'gr', vim.lsp.buf.references,     { desc = 'References' })
map('n', 'K',  vim.lsp.buf.hover,          { desc = 'Hover docs' })
map('n', '<leader>r', vim.lsp.buf.rename)
map('n', '<C-a>',   vim.lsp.buf.code_action, { desc = 'Code action' })
map('n', '<C-S-f>', function() vim.lsp.buf.format({ async = true }) end, { desc = 'Format' })

-- Diagnostics
map('n', '[d',    vim.diagnostic.goto_prev,  { desc = 'Prev diagnostic' })
map('n', ']d',    vim.diagnostic.goto_next,  { desc = 'Next diagnostic' })
map('n', '<C-e>', vim.diagnostic.open_float, { desc = 'Diagnostic float' })

-- Trouble
map('n', '<C-t>',   '<cmd>Trouble diagnostics toggle<cr>',              { desc = 'Trouble: all' })
map('n', '<C-S-t>', '<cmd>Trouble diagnostics toggle filter.buf=0<cr>', { desc = 'Trouble: buffer' })

-- Telescope
map('n', '<C-p>',   '<cmd>Telescope find_files<cr>',           { desc = 'Files' })
map('n', '<C-f>',   '<cmd>Telescope live_grep<cr>',            { desc = 'Grep' })
map('n', '<C-b>',   '<cmd>Telescope buffers<cr>',              { desc = 'Buffers' })
map('n', '<C-S-r>', '<cmd>Telescope oldfiles<cr>',             { desc = 'Recent files' })
map('n', '<C-S-o>', '<cmd>Telescope lsp_document_symbols<cr>', { desc = 'Symbols' })

-- File explorer
map('n', '<C-n>',   '<cmd>NvimTreeToggle<cr>',   { desc = 'Explorer toggle' })
map('n', '<C-S-n>', '<cmd>NvimTreeFindFile<cr>',  { desc = 'Explorer: find file' })

-- Git (Gitsigns)
-- kept as <leader> — <C-g> is a built-in Vim motion (file info)
map('n', '<leader>gb', '<cmd>Gitsigns toggle_current_line_blame<cr>', { desc = 'Git blame' })
map('n', '<leader>gp', '<cmd>Gitsigns preview_hunk<cr>',              { desc = 'Git preview hunk' })
map('n', '<leader>gs', '<cmd>Gitsigns stage_hunk<cr>',                { desc = 'Git stage hunk' })
map('n', '<leader>gr', '<cmd>Gitsigns reset_hunk<cr>',                { desc = 'Git reset hunk' })

-- Terminal
map('n', '<C-`>',   '<cmd>ToggleTerm direction=float<cr>',      { desc = 'Terminal float' })
map('n', '<C-S-`>', '<cmd>ToggleTerm direction=horizontal<cr>', { desc = 'Terminal horizontal' })
map('t', '<Esc>', [[<C-\><C-n>]], { desc = 'Exit terminal mode' })
map('t', 'kj',   [[<C-\><C-n>]], { desc = 'Exit terminal mode' })
