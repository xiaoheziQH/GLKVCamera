//
//  RShader.vsh
//  HelloOpenGL
//
//  Created by QiuH on 2017/9/20.
//  Copyright © 2017年 QiuH. All rights reserved.
//顶点着色器语句

uniform mat4 uMVPMatrix;

attribute vec4 a_position;
attribute vec2 a_texCoord;

varying vec2 v_texCoord;

void main()
{
    gl_Position = uMVPMatrix * a_position;
    v_texCoord = a_texCoord;
}
