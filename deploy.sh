#!/usr/bin/env bash
hexo clean
hexo g
hexo d
hexo clean
git add .
git commit -m '增加新文章'
git push