# Fundamentals of DevOps and Software Delivery Website

This is the website for the book _*[Fundamentals of DevOps and Software 
Delivery](https://www.fundamentals-of-devops.com)*_ by [Yevgeniy Brikman](https://www.ybrikman.com).

## Quick start

1. Make sure you have [Ruby](https://www.ruby-lang.org/) and [Jekyll](http://jekyllrb.com/docs/installation/) installed
1. `git clone` this repo
1. Just the first time: `bundle install`
1. To build the site and serve it: `bundle exec jekyll serve`
1. To test: `http://localhost:4000`

See the [Jekyll](http://jekyllrb.com/) and [GitHub Pages](https://pages.github.com/) documentation for more info.

## Technologies

1. Built with [Jekyll](http://jekyllrb.com/). This website is completely static.
2. Hosted on [GitHub Pages](https://pages.github.com/). I'm using the
   [GitHub Pages Gem](https://help.github.com/articles/using-jekyll-with-pages/) and only Jekyll plugins that are
   [available on GitHub Pages](https://help.github.com/articles/repository-metadata-on-github-pages/).
3. Free SSL and CDN provided by [CloudFlare](https://www.cloudflare.com/).    
4. I used [Basscss](http://www.basscss.com/), [Sass](http://sass-lang.com/),
   [Font Awesome Icons](http://fortawesome.github.io/Font-Awesome/icons/) (specifically, 
   [version 4.3](https://fontawesome.com/v4/icons/), and [Google Fonts](https://www.google.com/fonts) for styling.
6. I used [jQuery](https://jquery.com/) and [lazySizes](http://afarkas.github.io/lazysizes/) for behavior.
7. I'm using [UptimeRobot](http://uptimerobot.com/) and [Google Analytics](http://www.google.com/analytics/) for
   monitoring and metrics.

## Fetching outline data

The book's outline is defined in [`_data/outline.yml`](_data/outline.yml). Each chapter in the outline lists
a number of related books, other learning resources, and tools. To fetch reasonable images and descriptions of each
of these items, I wrote a script which uses various public APIs and a bit of screen scraping. 

To use the script:

1. Install Ruby.
2. Install dependencies:

    ```bash
    brew install imagemagick chromedriver
    gem install mini_magick nokogiri selenium-webdriver
    ```
3. Run the script:
   ```bash
   ruby fetch-outline-data.rb
   ```

It is idempotent, so it won't fetch images or descriptions for anything that already has it. However, for anything
that is missing that data, the script will do its best to find it, and then update `outline.yml` with this new data.
Commit the new `outline.yml` to update the website.

# License

This code is released under the MIT License. See LICENSE.txt.