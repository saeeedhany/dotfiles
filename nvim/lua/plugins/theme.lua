return {
    {
        "craftzdog/solarized-osaka.nvim",
        lazy = false,
        priority = 1000,
        config = function()
            require("solarized-osaka").setup({
                transparent = false,
                styles = { sidebars = "dark", floats = "dark" },
            })
            -- vim.cmd("colorscheme solarized-osaka")
        end,
    },
    {
        "ellisonleao/gruvbox.nvim",
        lazy = false,
        priority = 1000,
        config = function()
            require("gruvbox").setup({
                contrast = "hard",
                transparent_mode = true,
            })
            -- vim.cmd("colorscheme gruvbox")
        end,
    },
    {
        "rebelot/kanagawa.nvim",
        lazy = false,
        priority = 1000,
        config = function()
            require("kanagawa").setup({
                contrast = "hard",
                transparent_mode = true,
            })
            -- vim.cmd("colorscheme kanagawa-dragon")
        end,
    },
    {
        "saeeedhany/parchment.nvim",
        lazy = false,
        priority = 1000,
        config = function()
            require("parchment").setup({
                contrast = "hard",
                transparent_mode = true,
            })
            vim.cmd("colorscheme parchment")
        end,
    },
}
