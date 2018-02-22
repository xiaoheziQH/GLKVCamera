//
//  RShader.fsh
//  HelloOpenGL
//
//  Created by QiuH on 2017/9/20.
//  Copyright © 2017年 QiuH. All rights reserved.
//片元着色器语句


precision mediump float;

uniform sampler2D s_texture;

varying vec2 v_texCoord;

void main()
{
    gl_FragColor = texture2D(s_texture, v_texCoord);
}
